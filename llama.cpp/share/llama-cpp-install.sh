#!/usr/bin/env bash
# llama-cpp-install.sh — install / verify the Unsloth llama.cpp prebuilt that
# llama-server.service runs, and print the binary path.
#
# Layout (~/.local/opt/llama.cpp):
#   <tag>/          one unpacked bundle per release tag, never mutated in place
#   current -> <tag> symlink the service resolves through
#
# The Unsloth CUDA bundles are not self-contained: they link libcudart.so.13,
# libcublas.so.13 and libcublasLt.so.13 dynamically and expect a CUDA toolkit on
# the loader path. This host is WSL2 with the Windows driver only — no toolkit,
# no sudo — so the pinned NVIDIA redistributable runtime libs are unpacked next
# to llama-server, where the bundle's $ORIGIN rpath finds them. Only the shared
# objects are taken; headers, static archives and stubs are not.
#
# Evidence for that claim (`tar tzf app-b12649-mix-c7059d6-linux-x64-cuda13-
# portable.tar.gz` lists 61 entries, all ggml/llama objects): no libcudart,
# libcublas or libcublasLt member. libggml-cuda.so NEEDs libcudart.so.13 and
# libcublas.so.13, so the redist download below is required, not defensive.
#
# Modes:
#   ensure     install the pinned TAG if it is missing or incomplete; no network
#              access when the bundle is already complete (this is what the unit
#              runs in ExecStartPre)
#   verify     re-check the installed bundle and print its version
#   reinstall  re-download the *pinned* TAG, replacing the install atomically
#   check      ask GitHub whether a newer release exists; changes nothing
#   path       print the binary path the unit should run
#
# Bumping the version is a deliberate edit: set TAG and ASSET_SHA256 below, then
# `reinstall`. There is intentionally no `update <tag>` — a tag taken from the
# command line would have no pinned sha256 to verify against.
set -euo pipefail

# --- pinned inputs -----------------------------------------------------------
# A bump means new TAG + ASSET_SHA256 below, then `update` and a README refresh.
TAG="b12649-mix-c7059d6"
ASSET="app-${TAG}-linux-x64-cuda13-portable.tar.gz"
ASSET_SHA256="ceaa18c2dd2a2343afc3414691857564b0388d4c7317c332175eba2a47ce831f"
ASSET_URL="https://github.com/unslothai/llama.cpp/releases/download/${TAG}/${ASSET}"

# CUDA redistributable runtime the bundle was built against (toolkit 13.3).
# Versions and digests come from compute/cuda/redist/redistrib_13.3.0.json.
CUDA_REDIST_URL="https://developer.download.nvidia.cn/compute/cuda/redist"
RUNTIME_ARCHIVES=(
  "cuda_cudart/linux-x86_64/cuda_cudart-linux-x86_64-13.3.29-archive.tar.xz"
  "libcublas/linux-x86_64/libcublas-linux-x86_64-13.5.1.27-archive.tar.xz"
  "libnvjitlink/linux-x86_64/libnvjitlink-linux-x86_64-13.3.33-archive.tar.xz"
)
RUNTIME_SHA256=(
  "1e59c4888267d27ba1a9bd0f3669a6439db1334a96e754cd9013c7c73e18dc9d"
  "35a898360520d6101ffcaf36c0d04496b54d4fc2afb82f7fce44218c54513808"
  "f79e25bb1ef2f22f26c09897f6cb8719634f38e7330bd4700a1ea9ec9591eaff"
)
# Bare sonames ggml-cuda.so and its siblings ask the loader for.
RUNTIME_SONAMES=(libcudart.so.13 libcublas.so.13 libcublasLt.so.13 libnvJitLink.so.13)

OPT_DIR="${LLAMA_CPP_OPT_DIR:-$HOME/.local/opt/llama.cpp}"
PREFIX="$OPT_DIR/$TAG"
CURRENT="$OPT_DIR/current"

log() { echo "[llama-cpp-install] $*"; }
die() { echo "[llama-cpp-install] error: $*" >&2; exit 1; }

fetch() { # $1 = url, $2 = output path
  if command -v aria2c >/dev/null 2>&1; then
    # --no-conf: the user's aria2 config starts an RPC daemon and reads a
    # session file, which would collide with the running aria2 instance.
    aria2c --no-conf --continue=true --max-connection-per-server=8 --split=8 \
      --min-split-size=16M --file-allocation=none --auto-file-renaming=false \
      --allow-overwrite=true --console-log-level=warn --summary-interval=30 \
      --dir="$(dirname "$2")" --out="$(basename "$2")" "$1"
  else
    curl -fL --retry 5 --retry-delay 5 --continue-at - -o "$2" "$1"
  fi
}

sha_ok() { # $1 = file, $2 = expected sha256
  [ -f "$1" ] && [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$2" ]
}

installed() {
  [ -x "$PREFIX/llama-server" ] || return 1
  local soname
  for soname in "${RUNTIME_SONAMES[@]}"; do
    [ -e "$PREFIX/$soname" ] || return 1
  done
  [ -L "$CURRENT" ] && [ "$(readlink -f "$CURRENT")" = "$(readlink -f "$PREFIX")" ]
}

verify() {
  installed || die "bundle at $PREFIX is incomplete"
  local out
  out="$("$CURRENT/llama-server" --version 2>&1 | head -1)" ||
    die "llama-server --version failed"
  case "$out" in
    *"build 12649"*) log "$out" ;;
    *) log "warning: build string does not match the pinned tag: $out" ;;
  esac
}

install_bundle() {
  local work stage
  work="$(mktemp -d "${TMPDIR:-/tmp}/llama-cpp-install.XXXXXX")"
  stage="$OPT_DIR/.$TAG.stage"
  # shellcheck disable=SC2064  # expand work/stage now, not at trap time
  trap "rm -rf '$work' '$stage'" EXIT
  mkdir -p "$OPT_DIR"

  log "downloading $ASSET"
  fetch "$ASSET_URL" "$work/$ASSET"
  sha_ok "$work/$ASSET" "$ASSET_SHA256" ||
    die "$ASSET sha256 mismatch, want $ASSET_SHA256"

  local i archive extracted
  extracted="$work/runtime"
  mkdir -p "$extracted"
  for i in "${!RUNTIME_ARCHIVES[@]}"; do
    archive="$work/$(basename "${RUNTIME_ARCHIVES[$i]}")"
    log "downloading $(basename "${RUNTIME_ARCHIVES[$i]}")"
    fetch "$CUDA_REDIST_URL/${RUNTIME_ARCHIVES[$i]}" "$archive"
    sha_ok "$archive" "${RUNTIME_SHA256[$i]}" ||
      die "$(basename "$archive") sha256 mismatch, want ${RUNTIME_SHA256[$i]}"
    # each archive holds one <name>-<version>-archive/ tree; take only its lib/
    tar xJf "$archive" -C "$extracted" --strip-components=1 --wildcards '*/lib/*'
  done

  log "unpacking into $PREFIX"
  # Stage beside the target and swap: a half-unpacked bundle must never be
  # reachable through `current`.
  rm -rf "$stage"; mkdir -p "$stage"
  tar xzf "$work/$ASSET" -C "$stage"

  local soname
  for soname in "${RUNTIME_SONAMES[@]}"; do
    [ -e "$extracted/lib/$soname" ] || die "missing $soname in the runtime archives"
    cp -a "$extracted/lib/$soname"* "$stage/"
  done

  rm -rf "$PREFIX"
  mv "$stage" "$PREFIX"
  ln -sfn "$PREFIX" "$CURRENT"
  verify
}

check() {
  # Ask the releases API what the newest tag is. Read-only: never downloads a
  # bundle and never touches $CURRENT.
  local api="https://api.github.com/repos/unslothai/llama.cpp/releases/latest"
  local latest auth=()
  # Anonymous calls are rate-limited per egress IP and this host shares one, so
  # use a token when the user has gh configured. Without one the call still
  # works, just less often.
  local token="${GH_TOKEN:-}"
  [ -n "$token" ] || token="$(gh auth token 2>/dev/null || true)"
  [ -n "$token" ] && auth=(-H "Authorization: Bearer $token")
  latest="$(curl -fsSL --max-time 30 "${auth[@]}" "$api" 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null)" ||
    { log "could not reach $api (rate limit? set GH_TOKEN)"; return 1; }
  [ -n "$latest" ] || { log "release API returned no tag"; return 1; }
  if [ "$latest" = "$TAG" ]; then
    log "up to date (pinned $TAG is the latest release)"
    return 0
  fi
  log "a newer release exists: $latest (pinned: $TAG)"
  log "to move: set TAG and ASSET_SHA256 in this script, then run 'reinstall'"
  return 1
}

case "${1:-ensure}" in
  ensure)
    if installed; then
      log "$TAG present, current -> $TAG"
      exit 0
    fi
    log "bundle missing or incomplete, installing $TAG"
    install_bundle ;;
  verify) verify ;;
  reinstall) log "re-downloading pinned $TAG"; install_bundle ;;
  check) check ;;
  path) echo "$CURRENT/llama-server" ;;
  *) echo "usage: $0 {ensure|verify|reinstall|check|path}" >&2; exit 2 ;;
esac
