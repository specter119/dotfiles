#!/usr/bin/env bash
# qwen38-model-sync.sh — ensure / verify / update the Qwen3.8-27B IQ4_XS GGUF
# used by llama-server.service as ExecStartPre.
#
# The model lives in the default huggingface cache so other HF tools share it:
#   $HF_HUB_DIR/models--unsloth--Qwen3.8-27B-GGUF/Qwen3.8-27B-IQ4_XS.gguf
#
# It is idempotent: if the file exists with the expected size it exits 0
# (no network, no hashing). If missing/incomplete it re-downloads via hfd
# (aria2 multi-threaded, resumes partial downloads) and verifies sha256.
set -euo pipefail

REPO="unsloth/Qwen3.8-27B-GGUF"
FILE="Qwen3.8-27B-IQ4_XS.gguf"
HF_HUB_DIR="${HF_HUB_DIR:-$HOME/.cache/huggingface/hub}"
MODEL_DIR="$HF_HUB_DIR/models--unsloth--Qwen3.8-27B-GGUF"
MODEL="$MODEL_DIR/$FILE"
META="$MODEL_DIR/.hfd/repo_metadata.json"

# Fallbacks in case metadata is missing (source: HF repo_metadata.json, 2026-08-19)
FALLBACK_SIZE=15705861088
FALLBACK_SHA256="9fd40d7036f5e0918e20aaeebf11468fafd06bb53d4d980eef6bb7e4e4ace666"

meta_get() { # $1 = size|sha256  -> prints value from .hfd/repo_metadata.json
  [ -f "$META" ] || return 0
  python3 - "$META" "$FILE" "$1" <<'PY'
import json, sys
meta, fn, key = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    d = json.load(open(meta))
    for s in d.get("siblings", []):
        if s.get("rfilename") == fn:
            lfs = s.get("lfs") or {}
            print(lfs.get("size" if key == "size" else "sha256", ""))
            break
except Exception:
    pass
PY
}

expected_size()  { local v; v="$(meta_get size)";   echo "${v:-$FALLBACK_SIZE}"; }
expected_sha()   { local v; v="$(meta_get sha256)"; echo "${v:-$FALLBACK_SHA256}"; }
actual_size()    { stat -c %s "$MODEL" 2>/dev/null || echo 0; }

size_ok() {
  [ -f "$MODEL" ] && [ "$(actual_size)" = "$(expected_size)" ]
}

verify_sha() {
  local want got
  want="$(expected_sha)"
  got="$(sha256sum "$MODEL" | cut -d' ' -f1)"
  if [ "$got" = "$want" ]; then
    echo "[qwen38-sync] sha256 OK ($got)"
    return 0
  else
    echo "[qwen38-sync] sha256 MISMATCH: got $got, want $want" >&2
    return 1
  fi
}

download() {
  echo "[qwen38-sync] downloading $FILE ($(expected_size) bytes) via hfd -> $MODEL_DIR"
  mkdir -p "$MODEL_DIR"
  HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}" \
    hfd "$REPO" --include "$FILE" --local-dir "$MODEL_DIR" -x 8
}

ensure() {
  if size_ok; then
    echo "[qwen38-sync] model present and complete ($(actual_size) bytes)"
  else
    echo "[qwen38-sync] model missing or incomplete (have $(actual_size), want $(expected_size)); downloading"
    rm -f "$MODEL"          # hfd skips existing files, so drop the partial one
    download
    verify_sha
  fi
}

case "${1:-ensure}" in
  ensure) ensure ;;
  verify) [ -f "$MODEL" ] || { echo "[qwen38-sync] model not found" >&2; exit 1; }
          verify_sha ;;
  update) echo "[qwen38-sync] forcing re-download of $FILE"
          rm -f "$MODEL"
          download
          verify_sha ;;
  *) echo "usage: $0 {ensure|verify|update}" >&2; exit 2 ;;
esac
