#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=hooks/common.sh
. "$SCRIPT_DIR/common.sh"

payload="$(cat)"
source_name="$(printf '%s' "$payload" | session_start_source)"
bootstrap_context="$(print_bootstrap_context)"

case "$source_name" in
  startup|resume|clear)
    if [ -n "$bootstrap_context" ]; then
      printf '%s\n' "$bootstrap_context"
    fi
    ;;
  compact)
    if [ -n "$bootstrap_context" ]; then
      printf '%s\n\n' "$bootstrap_context"
    fi

    printf '%s\n' '---'
    printf '%s\n' 'Context was compacted. If you discovered important insights, distill them before continuing:'
    printf '%s\n' '  nmem --json m add "<insight>" -t "<short title>" -i 0.8 -s droid'
    ;;
esac
