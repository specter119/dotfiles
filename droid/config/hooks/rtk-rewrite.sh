#!/usr/bin/env bash
# RTK Droid hook: rewrites Execute commands to use rtk for token savings.
# Requires: rtk >= 0.23.0, jq
#
# Protocol: Droid PreToolUse hook (reads JSON from stdin, outputs JSON to stdout).
# Only processes tool_name == "Execute"; all others pass through silently.
#
# Exit code protocol for `rtk rewrite`:
#   0 + stdout  Rewrite found → output updatedInput
#   1           No RTK equivalent → pass through unchanged
#   2           Deny rule matched → pass through (Droid native deny handles it)
#   3 + stdout  Ask rule matched → rewrite but omit permissionDecision

if ! command -v jq &>/dev/null; then
  echo "[rtk] WARNING: jq is not installed. Hook cannot rewrite commands." >&2
  exit 0
fi

if ! command -v rtk &>/dev/null; then
  echo "[rtk] WARNING: rtk is not installed or not in PATH." >&2
  exit 0
fi

# Version guard: rtk rewrite was added in 0.23.0.
RTK_VERSION=$(rtk --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -n "$RTK_VERSION" ]; then
  MAJOR=$(echo "$RTK_VERSION" | cut -d. -f1)
  MINOR=$(echo "$RTK_VERSION" | cut -d. -f2)
  if [ "$MAJOR" -eq 0 ] && [ "$MINOR" -lt 23 ]; then
    echo "[rtk] WARNING: rtk $RTK_VERSION is too old (need >= 0.23.0)." >&2
    exit 0
  fi
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only process Execute tool calls.
if [ "$TOOL_NAME" != "Execute" ]; then
  exit 0
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

REWRITTEN=$(rtk rewrite "$CMD" 2>/dev/null)
EXIT_CODE=$?

case $EXIT_CODE in
  0)
    # Rewrite found. If identical, command already uses RTK.
    [ "$CMD" = "$REWRITTEN" ] && exit 0
    ;;
  1)
    # No RTK equivalent — pass through unchanged.
    exit 0
    ;;
  2)
    # Deny rule matched — let Droid's native handling fire.
    exit 0
    ;;
  3)
    # Ask rule matched — rewrite but omit permissionDecision so Droid prompts.
    ;;
  *)
    exit 0
    ;;
esac

ORIGINAL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')
UPDATED_INPUT=$(echo "$ORIGINAL_INPUT" | jq --arg cmd "$REWRITTEN" '.command = $cmd')

if [ "$EXIT_CODE" -eq 3 ]; then
  # Ask: rewrite the command, omit permissionDecision so Droid prompts user.
  jq -n \
    --argjson updated "$UPDATED_INPUT" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "updatedInput": $updated
      }
    }'
else
  # Allow: rewrite the command and auto-allow.
  jq -n \
    --argjson updated "$UPDATED_INPUT" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": "RTK auto-rewrite",
        "updatedInput": $updated
      }
    }'
fi
