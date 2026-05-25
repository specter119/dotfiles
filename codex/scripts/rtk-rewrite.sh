#!/bin/sh
# RTK Codex hook: thin delegator around `rtk rewrite`.
# Codex does not yet apply PreToolUse `updatedInput`, so rewrite results are
# returned as deny-with-suggestion.

if ! command -v jq >/dev/null 2>&1 || ! command -v rtk >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // .toolInput.command // empty' 2>/dev/null || true)

if [ -z "$cmd" ]; then
  exit 0
fi

rewritten=$(rtk rewrite "$cmd" 2>/dev/null)
status=$?

deny() {
  jq -n \
    --arg reason "$1" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": $reason
      }
    }'
}

case "$status" in
0 | 3)
  [ -z "$rewritten" ] || [ "$rewritten" = "$cmd" ] && exit 0
  deny "RTK rewrite required. Run this instead: $rewritten"
  ;;
2)
  deny "Blocked by RTK command policy."
  ;;
*)
  exit 0
  ;;
esac
