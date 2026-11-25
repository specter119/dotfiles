#!/usr/bin/env bash
# model-sync.sh — ensure / verify / update the Inkling-2-Mini GGUFs that
# llama-server.service loads, as ExecStartPre.
#
# Three files, all from unsloth/Inkling-2-Mini-GGUF:
#   Inkling-2-Mini-UD-Q4_K_XL.gguf       (17.6 GB)  target weights
#   mmproj-F16.gguf                      (639 MB)   vision projector
#   dspark-Inkling-2-Mini-Q8_0.gguf      (504 MB)   DSpark drafter
#
# They live in the default huggingface cache so other HF tools share them:
#   $HF_HUB_DIR/models--unsloth--Inkling-2-Mini-GGUF/<file>.gguf
#
# Idempotent: a file whose size matches the size the HF API reports for this
# revision exits 0 without touching the network (the API answer is cached next
# to the model). A missing or truncated file is fetched with aria2c
# (multi-connection, resumable) and checked against the API's sha256.
set -euo pipefail

REPO="unsloth/Inkling-2-Mini-GGUF"
MODEL_FILE="${MODEL_FILE:-Inkling-2-Mini-UD-Q4_K_XL.gguf}"
MMPROJ_FILE="${MMPROJ_FILE:-mmproj-F16.gguf}"
DRAFT_FILE="${DRAFT_FILE:-dspark-Inkling-2-Mini-Q8_0.gguf}"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
HF_HUB_DIR="${HF_HUB_DIR:-$HOME/.cache/huggingface/hub}"
MODEL_DIR="$HF_HUB_DIR/models--unsloth--Inkling-2-Mini-GGUF"
META="$MODEL_DIR/.hf-meta.json"   # {"<file>": {"size": N, "sha256": "..."}} from the HF API

# Refresh the cached size/sha256 table from the HF API (one small JSON request).
# A failure here is not fatal: `ensure` falls back to the on-disk check so a
# boot with no network still starts an already-populated model directory.
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
' "$META" || { echo "[model-sync] HF API unreachable, using cached metadata" >&2; return 1; }
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
  if [ -z "$v" ]; then refresh_meta || true; v="$(meta_get "$1" size)"; fi
  echo "$v"
}

expected_sha() { # $1 = file
  local v
  v="$(meta_get "$1" sha256)"
  if [ -z "$v" ]; then refresh_meta || true; v="$(meta_get "$1" sha256)"; fi
  echo "$v"
}

actual_size() { stat -c %s "$MODEL_DIR/$1" 2>/dev/null || echo 0; }

size_ok() { # $1 = file
  local want
  want="$(expected_size "$1")"
  if [ -n "$want" ]; then
    [ "$(actual_size "$1")" = "$want" ]
    return
  fi
  # No metadata (offline, no cached table): accept a non-empty file that aria2c
  # finished, i.e. one without a pending control file. A wrong-size file is
  # still caught by `verify`.
  echo "[model-sync] no size metadata, accepting $1 as-is (run 'verify' to check)" >&2
  [ -s "$MODEL_DIR/$1" ] && [ ! -e "$MODEL_DIR/$1.aria2" ]
}

verify_sha() { # $1 = file
  local want got
  want="$(expected_sha "$1")"
  if [ -z "$want" ]; then
    echo "[model-sync] no sha256 for $1 in HF metadata; skipping check" >&2
    return 0
  fi
  got="$(sha256sum "$MODEL_DIR/$1" | cut -d' ' -f1)"
  if [ "$got" = "$want" ]; then
    echo "[model-sync] $1 sha256 OK"
  else
    echo "[model-sync] $1 sha256 MISMATCH (got $got)" >&2
    return 1
  fi
}

download() { # $1 = file
  local url="$HF_ENDPOINT/$REPO/resolve/main/$1"
  echo "[model-sync] downloading $1 ($(expected_size "$1") bytes) -> $MODEL_DIR"
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
    echo "[model-sync] $1 present and complete ($(actual_size "$1") bytes)"
    return 0
  fi
  echo "[model-sync] $1 missing or incomplete (have $(actual_size "$1"), want $(expected_size "$1"))"
  download "$1"
  verify_sha "$1"
}

case "${1:-ensure}" in
  ensure)
    # The unit needs all three: weights, vision projector, drafter.
    ensure "$MODEL_FILE"
    ensure "$MMPROJ_FILE"
    ensure "$DRAFT_FILE" ;;
  # individual files, for one-off fetches outside a full start
  model) ensure "$MODEL_FILE" ;;
  mmproj) ensure "$MMPROJ_FILE" ;;
  draft) ensure "$DRAFT_FILE" ;;
  verify)
    rc=0
    for f in "$MODEL_FILE" "$MMPROJ_FILE" "$DRAFT_FILE"; do
      if [ -f "$MODEL_DIR/$f" ]; then
        verify_sha "$f" || rc=1
      else
        echo "[model-sync] $f not found" >&2
        rc=1
      fi
    done
    exit "$rc" ;;
  update)
    # Incremental: refresh the size/sha256 table, then re-fetch only the files
    # whose size or digest no longer matches. A re-quantised or re-uploaded file
    # changes size or sha256, so this is how a real upstream change is detected;
    # an unchanged file costs one metadata request, not 17.6 GB of download.
    echo "[model-sync] checking all three files against the HF API"
    refresh_meta || echo "[model-sync] HF API unreachable, comparing against cached metadata" >&2
    rc=0
    for f in "$MODEL_FILE" "$MMPROJ_FILE" "$DRAFT_FILE"; do
      if size_ok "$f" && verify_sha "$f" 2>/dev/null; then
        echo "[model-sync] $f unchanged, keeping it"
        continue
      fi
      echo "[model-sync] $f changed or incomplete, re-downloading"
      rm -f "$MODEL_DIR/$f" "$MODEL_DIR/$f.aria2"
      download "$f" || rc=1
      verify_sha "$f" || rc=1
    done
    exit "$rc" ;;
  *) echo "usage: $0 {ensure|model|mmproj|draft|verify|update}" >&2; exit 2 ;;
esac
