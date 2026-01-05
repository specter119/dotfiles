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
  local dirs=($(ls -td "$bin_dir"/*/ 2>/dev/null))
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
  local dirs=($(ls -td "$wsl_remote_dir"/*/ 2>/dev/null))
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

main() {
  log "Starting VSCode remote containers cleanup"
  clean_bin_dir
  clean_dist_dir
  clean_server_tar_host
  log "Cleanup completed successfully"
}

main "$@"
