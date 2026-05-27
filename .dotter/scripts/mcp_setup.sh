#!/bin/bash
set -euo pipefail

SHELL_BIN="bash"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--shell)
			SHELL_BIN="${2:-}"
			if [[ -z "$SHELL_BIN" ]]; then
				echo "missing value for --shell" >&2
				exit 1
			fi
			shift 2
			;;
		*)
			echo "unknown argument: $1" >&2
			exit 1
			;;
	esac
done

WINDSURF_KEY=$(rbw get windsurf-api-key 2>/dev/null || true)
export WINDSURF_KEY

run_shell() {
	"$SHELL_BIN" -lc "$1"
}

run_shell_allow_fail() {
	local cmd="$1"
	if [[ "$SHELL_BIN" == *fish ]]; then
		"$SHELL_BIN" -lc "$cmd; or true"
	else
		"$SHELL_BIN" -lc "$cmd || true"
	fi
}

run_shell_idempotent() {
	local cmd="$1"
	local output
	local status

	set +e
	output=$("$SHELL_BIN" -lc "$cmd" 2>&1)
	status=$?
	set -e

	if [[ $status -eq 0 ]]; then
		return 0
	fi

	if [[ "$output" == *"already exists"* ]]; then
		return 0
	fi

	if [[ -n "$output" ]]; then
		printf '%s\n' "$output" >&2
	fi
	return $status
}

cli_available() {
	run_shell "type -P $1 >/dev/null 2>&1"
}

ensure_claude_onboarding() {
	local claude_json="$HOME/.local/share/claude/.claude.json"
	if [[ -f "$claude_json" ]] && ! jq -e '.hasCompletedOnboarding == true' "$claude_json" >/dev/null 2>&1; then
		local tmp
		tmp=$(jq '.hasCompletedOnboarding = true' "$claude_json")
		printf '%s\n' "$tmp" >"$claude_json"
	fi
}

if cli_available claude; then
	run_shell_allow_fail 'claude mcp remove --scope user fast-context >/dev/null 2>&1'
	run_shell_allow_fail 'claude mcp remove --scope user morph-mcp >/dev/null 2>&1'
	run_shell_allow_fail 'claude mcp remove --scope user exa >/dev/null 2>&1'
	if [[ -n "$WINDSURF_KEY" ]]; then
		run_shell_idempotent 'claude mcp add --scope user fast-context -e WINDSURF_API_KEY="$WINDSURF_KEY" -- bunx fast-context-mcp >/dev/null'
		ensure_claude_onboarding
	fi
fi
