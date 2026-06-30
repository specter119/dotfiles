#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=hooks/common.sh
. "$SCRIPT_DIR/common.sh"

if ! ensure_nmem_command; then
  exit 0
fi

printf '%s\n' '[Nowledge Mem] Search past knowledge with nmem --json m search "query". Search prior sessions with nmem --json t search "query" -n 5. Save durable insights with nmem --json m add "content" -t "Title" -i 0.8 -s droid. For resumable checkpoints, use nmem --json t create -t "Session Handoff - <topic>" -c "Goal: ... Decisions: ... Files: ... Risks: ... Next: ..." -s droid. Do not claim save-thread unless a real Droid transcript importer exists.'
