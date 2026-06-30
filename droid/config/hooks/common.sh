#!/usr/bin/env bash

ensure_nmem_command() {
  command -v nmem >/dev/null 2>&1
}

session_start_source() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, sys; print(json.load(sys.stdin).get("source", ""))' 2>/dev/null
    return
  fi

  tr -d "\r\n" | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

read_context_bundle() {
  command -v python3 >/dev/null 2>&1 || return 1
  ensure_nmem_command || return 1

  local -a args=(context --source-app droid)
  local space=""

  if [ -n "${NMEM_AGENT_ID:-}" ]; then
    args+=(--agent-id "$NMEM_AGENT_ID")
  fi

  if [ -n "${NMEM_HOST_AGENT_ID:-}" ]; then
    args+=(--host-agent-id "$NMEM_HOST_AGENT_ID")
  fi

  space="${NMEM_SPACE:-}"
  if [ -z "$space" ]; then
    space="${NMEM_SPACE_ID:-}"
  fi

  if [ -n "$space" ]; then
    args+=(--space "$space")
  fi

  nmem --json "${args[@]}" 2>/dev/null | python3 -c 'import json, sys; data = json.load(sys.stdin); content = data.get("rendered_markdown") or data.get("markdown") or data.get("content") or ""; print(content) if content else sys.exit(1)' 2>/dev/null
}

read_working_memory() {
  ensure_nmem_command || return 1

  if command -v python3 >/dev/null 2>&1; then
    nmem --json wm read 2>/dev/null | python3 -c 'import json, sys; data = json.load(sys.stdin); content = data.get("content", ""); print(content) if data.get("exists") and content else sys.exit(1)' 2>/dev/null
    return
  fi

  nmem wm read 2>/dev/null
}

print_bootstrap_context() {
  read_context_bundle || read_working_memory || cat ~/ai-now/memory.md 2>/dev/null || true
}
