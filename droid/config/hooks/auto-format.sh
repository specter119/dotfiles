#!/usr/bin/env bash
set -uo pipefail

warn() {
  printf 'auto-format: %s\n' "$*" >&2
}

prepend_path() {
  local entry="$1"
  [ -d "$entry" ] || return 0
  case ":${PATH:-}:" in
    *":$entry:"*) return 0 ;;
  esac
  PATH="$entry${PATH:+:$PATH}"
}

PATH="${PATH:-}"
prepend_path /bin
prepend_path /usr/bin
prepend_path /usr/local/bin
if [ -n "${HOME:-}" ]; then
  prepend_path "$HOME/.nix-profile/bin"
  prepend_path "${CARGO_HOME:-$HOME/.cargo}/bin"
  prepend_path "${BUN_INSTALL:-$HOME/.bun}/bin"
  prepend_path "${UV_TOOL_BIN_DIR:-$HOME/.local/bin}"
  prepend_path "${XDG_BIN_HOME:-$HOME/.local/bin}"
  prepend_path "$HOME/.local/bin"
fi
[ -n "${CARGO_HOME:-}" ] && prepend_path "$CARGO_HOME/bin"
[ -n "${BUN_INSTALL:-}" ] && prepend_path "$BUN_INSTALL/bin"
[ -n "${UV_TOOL_BIN_DIR:-}" ] && prepend_path "$UV_TOOL_BIN_DIR"
[ -n "${XDG_BIN_HOME:-}" ] && prepend_path "$XDG_BIN_HOME"
export PATH

if ! command -v python3 >/dev/null 2>&1; then
  warn 'python3 is unavailable; skipping file path extraction'
  exit 1
fi

file_paths=()
mapfile -d '' -t file_paths < <(python3 -c '
import json
import os
import re
import sys
from pathlib import Path

try:
    event = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    print("auto-format: invalid Droid hook input", file=sys.stderr)
    raise SystemExit(0)

if event.get("hook_event_name") != "PostToolUse":
    raise SystemExit(0)

tool_name = event.get("tool_name")
if tool_name not in {"Create", "Edit", "Write", "ApplyPatch"}:
    raise SystemExit(0)

tool_input = event.get("tool_input")
if not isinstance(tool_input, dict):
    raise SystemExit(0)

raw_paths = []
def add_path(value):
    if isinstance(value, str):
        if value and value.strip():
            raw_paths.append(value)
    elif isinstance(value, list):
        for item in value:
            add_path(item)
    elif isinstance(value, dict):
        for key in ("file_path", "filePath", "path"):
            if key in value:
                add_path(value[key])

for key in ("file_path", "filePath", "path", "files", "file_paths", "paths"):
    if key in tool_input:
        add_path(tool_input[key])

if tool_name == "ApplyPatch":
    patch_texts = [
        tool_input.get(key)
        for key in ("patch", "diff", "unified_diff")
        if isinstance(tool_input.get(key), str)
    ]
    for patch_text in patch_texts:
        for line in patch_text.splitlines():
            match = re.match(r"^\*\*\* (?:(?:Update|Add) File|Move to(?: File)?):\s*(.+?)\s*$", line)
            if match:
                raw_paths.append(match.group(1))
                continue
            match = re.match(r"^diff --git a/.* b/(.+)$", line)
            if match:
                raw_paths.append(match.group(1))

response = event.get("tool_response")
if isinstance(response, dict):
    for key in ("file_path", "filePath", "path", "files"):
        if key in response:
            add_path(response[key])

raw_cwd = event.get("cwd")
if not isinstance(raw_cwd, str) or not raw_cwd.strip():
    raw_cwd = os.getcwd()
try:
    root = Path(raw_cwd).expanduser().resolve(strict=True)
except (OSError, RuntimeError):
    print("auto-format: invalid session cwd; skipping", file=sys.stderr)
    raise SystemExit(0)
if not root.is_dir():
    raise SystemExit(0)

seen = set()
for raw_path in raw_paths:
    try:
        path = Path(raw_path).expanduser()
        if not path.is_absolute():
            path = root / path
        path = path.resolve(strict=True)
    except (OSError, RuntimeError, ValueError):
        continue
    if not path.is_file():
        continue
    try:
        path.relative_to(root)
    except ValueError:
        print(f"auto-format: refusing path outside session cwd: {path}", file=sys.stderr)
        continue
    value = str(path)
    if value not in seen:
        seen.add(value)
        sys.stdout.buffer.write(os.fsencode(value) + b"\0")
')

if [ "${#file_paths[@]}" -eq 0 ]; then
  exit 0
fi

run_formatter() {
  local name="$1"
  local file_path="$2"
  shift 2

  local status=0
  if command -v timeout >/dev/null 2>&1; then
    if timeout 60s "$@" >/dev/null; then
      return 0
    else
      status=$?
    fi
  else
    if "$@" >/dev/null; then
      return 0
    else
      status=$?
    fi
  fi

  warn "$name failed for $file_path (exit $status)"
  return 1
}

rust_edition_for_file() {
  python3 - "$1" <<'PY'
import sys
from pathlib import Path

valid_editions = {"2015", "2018", "2021", "2024"}
target = Path(sys.argv[1])
directories = [target.parent, *target.parent.parents]
manifests = []

try:
    import tomllib
except ImportError:
    raise SystemExit(1)

for directory in directories:
    manifest = directory / "Cargo.toml"
    if not manifest.is_file():
        continue
    try:
        data = tomllib.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        continue
    manifests.append((directory, data))

for index, (_, data) in enumerate(manifests):
    package = data.get("package")
    if not isinstance(package, dict):
        continue
    edition = package.get("edition")
    if edition is None:
        print("2015")
        raise SystemExit(0)
    if isinstance(edition, int):
        edition = str(edition)
    if isinstance(edition, str) and edition in valid_editions:
        print(edition)
        raise SystemExit(0)
    inherits_workspace = edition == "workspace" or (
        isinstance(edition, dict) and edition.get("workspace") is True
    )
    if inherits_workspace:
        for _, ancestor_data in manifests[index:]:
            workspace_edition = (
                ancestor_data.get("workspace", {})
                .get("package", {})
                .get("edition")
            )
            if isinstance(workspace_edition, int):
                workspace_edition = str(workspace_edition)
            if isinstance(workspace_edition, str) and workspace_edition in valid_editions:
                print(workspace_edition)
                raise SystemExit(0)
    raise SystemExit(1)

for _, data in manifests:
    workspace_edition = (
        data.get("workspace", {}).get("package", {}).get("edition")
    )
    if isinstance(workspace_edition, int):
        workspace_edition = str(workspace_edition)
    if isinstance(workspace_edition, str) and workspace_edition in valid_editions:
        print(workspace_edition)
        raise SystemExit(0)

for directory in directories:
    for name in ("rustfmt.toml", ".rustfmt.toml"):
        config_path = directory / name
        if not config_path.is_file():
            continue
        try:
            config = tomllib.loads(config_path.read_text(encoding="utf-8"))
        except (OSError, tomllib.TOMLDecodeError):
            continue
        edition = config.get("edition")
        if isinstance(edition, int):
            edition = str(edition)
        if isinstance(edition, str) and edition in valid_editions:
            print(edition)
            raise SystemExit(0)

raise SystemExit(1)
PY
}

rustfmt_config_for_file() {
  local directory="${1%/*}"
  while :; do
    for name in rustfmt.toml .rustfmt.toml; do
      if [ -f "$directory/$name" ]; then
        printf '%s\n' "$directory/$name"
        return 0
      fi
    done
    [ "$directory" = "/" ] && break
    directory="${directory%/*}"
    [ -n "$directory" ] || directory="/"
  done
}

format_rust_file() {
  local file_path="$1"
  local edition
  edition="$(rust_edition_for_file "$file_path" 2>/dev/null)" || edition=""
  if [ -z "$edition" ]; then
    warn "could not determine Rust edition; skipping $file_path"
    return 0
  fi
  if ! command -v rustfmt >/dev/null 2>&1; then
    warn "rustfmt is unavailable; skipping $file_path"
    return 0
  fi

  local file_dir="${file_path%/*}"
  local temp_dir
  temp_dir="$(mktemp -d "$file_dir/.droid-auto-format.XXXXXX")" || {
    warn "could not create Rust formatter temp directory for $file_path"
    return 1
  }
  local temp_source="$temp_dir/source.rs"
  local temp_original="$temp_dir/original.rs"
  if ! cp -p "$file_path" "$temp_original" || ! cp -p "$temp_original" "$temp_source"; then
    rm -rf "$temp_dir"
    warn "could not stage $file_path for rustfmt"
    return 1
  fi

  local -a args=(--edition "$edition" --config skip_children=true)
  local rustfmt_config
  rustfmt_config="$(rustfmt_config_for_file "$file_path")"
  if [ -n "$rustfmt_config" ]; then
    args+=(--config-path "$rustfmt_config")
  fi
  args+=("$temp_source")

  if ! run_formatter rustfmt "$file_path" rustfmt "${args[@]}"; then
    rm -rf "$temp_dir"
    return 1
  fi
  if ! cmp -s "$file_path" "$temp_original"; then
    rm -rf "$temp_dir"
    warn "file changed concurrently; skipped Rust formatting for $file_path"
    return 1
  fi
  if ! mv -f "$temp_source" "$file_path"; then
    rm -rf "$temp_dir"
    warn "could not atomically replace $file_path with rustfmt output"
    return 1
  fi

  rm -rf "$temp_dir"
}

format_file() (
  local file_path="$1"
  local lower_path="${file_path,,}"

  [ -f "$file_path" ] || exit 0
  cd "${file_path%/*}" || {
    warn "could not enter file directory for $file_path"
    exit 1
  }

  case "$lower_path" in
    *.py|*.pyi)
      if command -v ruff >/dev/null 2>&1; then
        run_formatter ruff "$file_path" ruff format "$file_path"
      elif command -v uvx >/dev/null 2>&1; then
        run_formatter ruff "$file_path" uvx --from "ruff==0.16.8" ruff format "$file_path"
      else
        warn "ruff and uvx are unavailable; skipping $file_path"
      fi
      ;;
    *.ts|*.tsx|*.mts|*.cts|*.js|*.jsx|*.mjs|*.cjs)
      local biome_version=""
      if command -v biome >/dev/null 2>&1; then
        biome_version="$(biome --version 2>/dev/null || true)"
      fi
      if [[ "$biome_version" == *2.5.14* ]]; then
        run_formatter biome "$file_path" biome format --write "$file_path"
      elif command -v bunx >/dev/null 2>&1; then
        run_formatter biome "$file_path" bunx "@biomejs/biome@2.5.14" format --write "$file_path"
      else
        warn "Biome 2.5.14 and bunx are unavailable; skipping $file_path"
      fi
      ;;
    *.md|*.markdown)
      local mdformat_version=""
      if command -v mdformat >/dev/null 2>&1; then
        mdformat_version="$(mdformat --version 2>/dev/null || true)"
      fi
      if [[ "$mdformat_version" == *mdformat-gfm* && "$mdformat_version" == *mdformat_front_matters* ]]; then
        run_formatter mdformat "$file_path" mdformat --wrap keep "$file_path"
      elif command -v uvx >/dev/null 2>&1; then
        run_formatter mdformat "$file_path" uvx --from mdformat==1.0.0 --with mdformat-gfm==1.0.0 --with mdformat-front-matters==2.0.0 mdformat --wrap keep "$file_path"
      else
        warn "mdformat with GFM/front-matter plugins and uvx are unavailable; skipping $file_path"
      fi
      ;;
    *.rs)
      format_rust_file "$file_path"
      ;;
  esac
)

format_failed=0
for file_path in "${file_paths[@]}"; do
  if ! format_file "$file_path"; then
    format_failed=1
  fi
done

exit "$format_failed"
