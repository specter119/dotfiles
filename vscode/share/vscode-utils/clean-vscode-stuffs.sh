#!/bin/bash

# Clean up VSCode remote containers directories
set -euo pipefail

# Environment variable for Windows user profile path (Linux path)
UserProfileLinux="${WSL_WIN_HOME:?WSL_WIN_HOME environment variable not set}"
LOG_IDENT="clean-vscode-containers"
LOG_CMD="logger -t $LOG_IDENT"

log() {
  echo "$1"
  $LOG_CMD "$1"
}

clean_bin_dir() {
  local bin_dir="$HOME/.vscode-remote-containers/bin"
  if [ ! -d "$bin_dir" ]; then
    log "Bin directory $bin_dir does not exist"
    return
  fi

  # Get directories sorted by modification time (newest first)
  readarray -t dirs < <(ls -td "$bin_dir"/*/ 2>/dev/null)
  if [ ${#dirs[@]} -eq 0 ]; then
    log "No directories found in $bin_dir"
    return
  fi

  local latest_dir="${dirs[0]}"
  log "Keeping latest bin directory: $latest_dir"

  # Remove all older directories with logging
  for dir in "${dirs[@]:1}"; do
    log "Removing old directory: $dir"
    rm -rf "$dir"
  done
}

clean_dist_dir() {
  local dist_dir="$HOME/.vscode-remote-containers/dist"
  if [ ! -d "$dist_dir" ]; then
    log "Dist directory $dist_dir does not exist"
    return
  fi

  # Keep latest vscode-remote-containers-server-*.js
  local server_js=$(ls -t "$dist_dir"/vscode-remote-containers-server-*.js 2>/dev/null | head -n1)
  if [ -n "$server_js" ]; then
    log "Keeping latest server JS: $server_js"
    find "$dist_dir" -name "vscode-remote-containers-server-*.js" ! -path "$server_js" -delete
  fi

  # Keep latest dev-containers-cli-* folder
  local latest_cli=$(ls -td "$dist_dir"/dev-containers-cli-* 2>/dev/null | head -n1)
  if [ -n "$latest_cli" ]; then
    log "Keeping latest CLI folder: $latest_cli"
    find "$dist_dir" -name "dev-containers-cli-*" -type d ! -path "$latest_cli" -exec rm -rf {} +
  fi
}

clean_server_tar_host() {
  local wsl_remote_dir="$UserProfileLinux/vscode-remote-wsl/insider"

  if [ ! -d "$wsl_remote_dir" ]; then
    log "WSL remote directory $wsl_remote_dir does not exist"
    return
  fi

  # Get directories sorted by modification time (newest first)
  readarray -t dirs < <(ls -td "$wsl_remote_dir"/*/ 2>/dev/null)
  if [ ${#dirs[@]} -eq 0 ]; then
    log "No directories found in $wsl_remote_dir"
    return
  fi

  local latest_dir="${dirs[0]}"
  log "Keeping latest WSL remote directory: $latest_dir"

  # Remove all older directories with logging
  for dir in "${dirs[@]:1}"; do
    log "Removing old WSL remote directory: $dir"
    rm -rf "$dir"
  done
}

clean_win_extensions() {
  local ext_dir="$UserProfileLinux/.vscode-insiders/extensions"

  if [ ! -d "$ext_dir" ]; then
    log "Windows extensions directory $ext_dir does not exist"
    return
  fi

  # Remove all UUID-like hidden directories (start with .)
  # These are temporary/residual folders from extension installation
  local count=0
  while IFS= read -r -d '' dir; do
    log "Removing obsolete extension cache: $dir"
    rm -rf "$dir"
    ((count++)) || true
  done < <(find "$ext_dir" -maxdepth 1 -type d -name ".[0-9a-f]*-[0-9a-f]*-[0-9a-f]*-[0-9a-f]*-[0-9a-f]*" -print0)

  log "Cleaned $count obsolete extension cache directories"

  # Remove old versions of extensions, keeping only the newest
  # Extension format: publisher.name-version[-platform]
  declare -A latest_ext
  declare -A latest_time

  while IFS= read -r dir; do
    local basename=$(basename "$dir")
    # Skip hidden directories
    [[ "$basename" == .* ]] && continue
    # Extract extension ID (publisher.name) by removing version suffix
    # Match: publisher.name-X.Y.Z or publisher.name-X.Y.Z-platform
    local ext_id=$(echo "$basename" | sed -E 's/-[0-9]+\.[0-9]+\.[0-9]+.*$//')
    [[ -z "$ext_id" ]] && continue

    local mtime=$(stat -c %Y "$dir" 2>/dev/null || echo 0)

    if [[ -z "${latest_time[$ext_id]:-}" ]] || (( mtime > latest_time[$ext_id] )); then
      # Remove previous latest if exists
      if [[ -n "${latest_ext[$ext_id]:-}" ]]; then
        log "Removing old extension version: ${latest_ext[$ext_id]}"
        rm -rf "${latest_ext[$ext_id]}"
      fi
      latest_ext[$ext_id]="$dir"
      latest_time[$ext_id]=$mtime
    else
      log "Removing old extension version: $dir"
      rm -rf "$dir"
    fi
  done < <(find "$ext_dir" -maxdepth 1 -type d -mindepth 1)

  log "Extension cleanup completed"
}

main() {
  log "Starting VSCode remote containers cleanup"
  clean_bin_dir
  clean_dist_dir
  clean_server_tar_host
  clean_win_extensions
  log "Cleanup completed successfully"
}

main "$@"
