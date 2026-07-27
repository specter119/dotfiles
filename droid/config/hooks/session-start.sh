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
    emit_hook_context "SessionStart" "$bootstrap_context"
    ;;
  compact)
    context_text="$bootstrap_context"
    if [ -n "$context_text" ]; then
      context_text="${context_text}

"
    fi
    context_text="${context_text}---
Context was compacted. If you discovered important insights, distill them before continuing:
  nmem --json m add \"<insight>\" -t \"<short title>\" -i 0.8 -s droid"
    emit_hook_context "SessionStart" "$context_text"
    ;;
esac
