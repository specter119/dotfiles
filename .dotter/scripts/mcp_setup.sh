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

cli_available() {
	run_shell "type -P $1 >/dev/null 2>&1"
}

supports_mcp() {
	run_shell "$1 mcp list >/dev/null 2>&1"
}

ensure_claude_onboarding() {
	local claude_json="$HOME/.local/share/claude/.claude.json"
	if [[ -f "$claude_json" ]] && ! jq -e '.hasCompletedOnboarding == true' "$claude_json" >/dev/null 2>&1; then
		local tmp
		tmp=$(jq '.hasCompletedOnboarding = true' "$claude_json")
		printf '%s\n' "$tmp" >"$claude_json"
	fi
}

if [[ "${ENABLED_PACKAGES:-}" == *" claude-code "* ]] && cli_available claude; then
	if [[ -n "${MORPH_KEY:-}" && -n "${EXA_KEY:-}" ]]; then
		run_shell_allow_fail 'claude mcp remove --scope user morph-mcp >/dev/null 2>&1'
		run_shell 'claude mcp add --scope user morph-mcp -e MORPH_API_KEY="$MORPH_KEY" -e ENABLED_TOOLS=edit_file,warpgrep_codebase_search -- bunx @morphllm/morphmcp >/dev/null'
		run_shell_allow_fail 'claude mcp remove --scope user exa >/dev/null 2>&1'
		run_shell 'claude mcp add --scope user exa -e EXA_API_KEY="$EXA_KEY" -- bunx exa-mcp-server "tools=web_search_exa,get_code_context_exa,crawling_exa" >/dev/null'
		ensure_claude_onboarding
	fi
fi

if [[ "${ENABLED_PACKAGES:-}" == *" codex "* ]] && cli_available codex; then
	if [[ -n "${MORPH_KEY:-}" && -n "${EXA_KEY:-}" && -n "${CONTEXT7_KEY:-}" ]]; then
		run_shell_allow_fail 'codex mcp remove morph-mcp >/dev/null 2>&1'
		run_shell 'codex mcp add morph-mcp --env MORPH_API_KEY="$MORPH_KEY" --env ENABLED_TOOLS=edit_file,warpgrep_codebase_search -- bunx @morphllm/morphmcp >/dev/null'
		run_shell_allow_fail 'codex mcp remove exa >/dev/null 2>&1'
		run_shell 'codex mcp add exa --env EXA_API_KEY="$EXA_KEY" -- bunx exa-mcp-server "tools=web_search_exa,get_code_context_exa,crawling_exa" >/dev/null'
		run_shell_allow_fail 'codex mcp remove context7 >/dev/null 2>&1'
		run_shell 'codex mcp add context7 -- bunx @upstash/context7-mcp --api-key "$CONTEXT7_KEY" >/dev/null'
	fi
fi

if [[ "${ENABLED_PACKAGES:-}" == *" gemini "* ]] && cli_available gemini && supports_mcp gemini; then
	if [[ -n "${MORPH_KEY:-}" && -n "${EXA_KEY:-}" && -n "${CONTEXT7_KEY:-}" ]]; then
		run_shell_allow_fail 'gemini mcp remove -s user morph-mcp >/dev/null 2>&1'
		run_shell 'gemini mcp add -s user -e MORPH_API_KEY="$MORPH_KEY" -e ENABLED_TOOLS=edit_file,warpgrep_codebase_search morph-mcp bunx @morphllm/morphmcp >/dev/null'
		run_shell_allow_fail 'gemini mcp remove -s user exa >/dev/null 2>&1'
		run_shell 'gemini mcp add -s user -e EXA_API_KEY="$EXA_KEY" exa bunx exa-mcp-server "tools=web_search_exa,get_code_context_exa,crawling_exa" >/dev/null'
		run_shell_allow_fail 'gemini mcp remove -s user context7 >/dev/null 2>&1'
		run_shell 'gemini mcp add -s user -e CONTEXT7_KEY="$CONTEXT7_KEY" context7 bunx @upstash/context7-mcp --api-key "$CONTEXT7_KEY" >/dev/null'
	fi
fi
