#!/usr/bin/env bash
# qwen38-model-sync.sh — ensure / verify / update the Qwen3.8-27B GGUF used by
# llama-server.service as ExecStartPre.
#
# Files live in the default huggingface cache so other HF tools share them:
#   $HF_HUB_DIR/models--unsloth--Qwen3.8-27B-GGUF/<file>.gguf
#
# Idempotent: a file whose size matches the size the HF API reports for this
# revision exits 0 without touching the network (the API answer is cached next
# to the model). A missing or truncated file is fetched with aria2c
# (multi-connection, resumable) and checked against the API's sha256.
set -euo pipefail

REPO="unsloth/Qwen3.8-27B-GGUF"
MODEL_FILE="${MODEL_FILE:-Qwen3.8-27B-UD-Q4_K_XL.gguf}"
MMPROJ_FILE="${MMPROJ_FILE:-mmproj-F16.gguf}"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
HF_HUB_DIR="${HF_HUB_DIR:-$HOME/.cache/huggingface/hub}"
MODEL_DIR="$HF_HUB_DIR/models--unsloth--Qwen3.8-27B-GGUF"
META="$MODEL_DIR/.hf-meta.json"   # {"<file>": {"size": N, "sha256": "..."}} from the HF API

# Refresh the cached size/sha256 table from the HF API (one small JSON request).
refresh_meta() {
  mkdir -p "$MODEL_DIR"
  curl -fsSL --max-time 30 "$HF_ENDPOINT/api/models/$REPO/tree/main" |
    python3 -c '
import json, sys
out = {}
for f in json.load(sys.stdin):
    if not isinstance(f, dict) or f.get("type") != "file":
        continue
    lfs = f.get("lfs") or {}
    # for LFS files the API reports the content sha256 as lfs.oid
    out[f["path"]] = {"size": lfs.get("size") or f.get("size"), "sha256": lfs.get("sha256") or lfs.get("oid")}
json.dump(out, open(sys.argv[1], "w"), indent=1)
' "$META"
}

meta_get() { # $1 = file, $2 = size|sha256
  python3 - "$META" "$1" "$2" <<'PY'
import json, sys
try:
    entry = json.load(open(sys.argv[1])).get(sys.argv[2], {})
except Exception:
    entry = {}
print(entry.get(sys.argv[3]) or "")
PY
}

expected_size() { # $1 = file
  local v
  v="$(meta_get "$1" size)"
  if [ -z "$v" ]; then refresh_meta; v="$(meta_get "$1" size)"; fi
  echo "$v"
}

expected_sha() { # $1 = file
  local v
  v="$(meta_get "$1" sha256)"
  if [ -z "$v" ]; then refresh_meta; v="$(meta_get "$1" sha256)"; fi
  echo "$v"
}

actual_size() { stat -c %s "$MODEL_DIR/$1" 2>/dev/null || echo 0; }

size_ok() { # $1 = file
  local want
  want="$(expected_size "$1")"
  [ -n "$want" ] && [ "$(actual_size "$1")" = "$want" ]
}

verify_sha() { # $1 = file
  local want got
  want="$(expected_sha "$1")"
  if [ -z "$want" ]; then
    echo "[qwen38-sync] no sha256 for $1 in HF metadata; skipping check" >&2
    return 0
  fi
  got="$(sha256sum "$MODEL_DIR/$1" | cut -d' ' -f1)"
  if [ "$got" = "$want" ]; then
    echo "[qwen38-sync] $1 sha256 OK"
  else
    echo "[qwen38-sync] $1 sha256 MISMATCH (got $got)" >&2
    return 1
  fi
}

download() { # $1 = file
  local url="$HF_ENDPOINT/$REPO/resolve/main/$1"
  echo "[qwen38-sync] downloading $1 ($(expected_size "$1") bytes) -> $MODEL_DIR"
  mkdir -p "$MODEL_DIR"
  # --no-conf: the user's ~/.config/aria2/aria2.conf enables RPC and reads a
  # session file, which would collide with the aria2 daemon and fail here.
  # --continue resumes a partial file; the .aria2 control file is kept on
  # failure so a restart picks up where it stopped instead of starting over.
  aria2c --no-conf --continue=true --max-connection-per-server=8 --split=8 \
    --min-split-size=16M --file-allocation=none --auto-file-renaming=false \
    --allow-overwrite=true --console-log-level=warn --summary-interval=30 \
    --dir="$MODEL_DIR" --out="$1" "$url"
}

ensure() { # $1 = file
  if size_ok "$1"; then
    echo "[qwen38-sync] $1 present and complete ($(actual_size "$1") bytes)"
    return 0
  fi
  echo "[qwen38-sync] $1 missing or incomplete (have $(actual_size "$1"), want $(expected_size "$1"))"
  download "$1"
  verify_sha "$1"
}

case "${1:-ensure}" in
  ensure) ensure "$MODEL_FILE" ;;
  mmproj) ensure "$MMPROJ_FILE" ;;
  verify) [ -f "$MODEL_DIR/$MODEL_FILE" ] || { echo "[qwen38-sync] model not found" >&2; exit 1; }
          verify_sha "$MODEL_FILE" ;;
  update) echo "[qwen38-sync] forcing re-download of $MODEL_FILE"
          rm -f "$MODEL_DIR/$MODEL_FILE" "$MODEL_DIR/$MODEL_FILE.aria2"
          refresh_meta
          download "$MODEL_FILE"
          verify_sha "$MODEL_FILE" ;;
  *) echo "usage: $0 {ensure|mmproj|verify|update}" >&2; exit 2 ;;
esac
