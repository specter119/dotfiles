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

CONTEXT7_KEY=$(rbw get context7-api-key 2>/dev/null || true)
WINDSURF_KEY=$(rbw get windsurf-api-key 2>/dev/null || true)
export CONTEXT7_KEY WINDSURF_KEY

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

patch_codex_mcp_config() {
	local config_path="$HOME/.config/codex/config.toml"
	if [[ ! -f "$config_path" ]]; then
		return 0
	fi

	CONFIG_PATH="$config_path" \
	CONTEXT7_KEY="$CONTEXT7_KEY" \
	WINDSURF_KEY="$WINDSURF_KEY" \
	python3 - <<'PY'
import json
import os
from pathlib import Path
import tomllib

config_path = Path(os.environ["CONFIG_PATH"])
text = config_path.read_text(encoding="utf-8")
data = tomllib.loads(text)

if not isinstance(data, dict):
    raise SystemExit("codex config root must be a TOML table")

def format_key(key: str) -> str:
    if key and all(ch.isalnum() or ch in {"_", "-"} for ch in key):
        return key
    return json.dumps(key)

def format_value(value):
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if value != value or value in (float("inf"), float("-inf")):
            raise SystemExit("unsupported float value in codex config")
        return repr(value)
    if isinstance(value, list):
        return "[" + ", ".join(format_value(item) for item in value) + "]"
    raise SystemExit(f"unsupported TOML value type: {type(value).__name__}")

def write_table(lines: list[str], path: list[str], table: dict):
    scalars = []
    subtables = []
    for key, value in table.items():
        if isinstance(value, dict):
            subtables.append((key, value))
        else:
            scalars.append((key, value))

    if path:
        lines.append("[" + ".".join(format_key(part) for part in path) + "]")

    for key, value in scalars:
        lines.append(f"{format_key(key)} = {format_value(value)}")

    for index, (key, value) in enumerate(subtables):
        if lines and lines[-1] != "":
            lines.append("")
        write_table(lines, [*path, key], value)
        if index != len(subtables) - 1:
            lines.append("")

mcp_servers = data.get("mcp_servers")
if mcp_servers is None:
    mcp_servers = {}
    data["mcp_servers"] = mcp_servers
elif not isinstance(mcp_servers, dict):
    raise SystemExit("mcp_servers must be a TOML table")

mcp_servers.pop("morph-mcp", None)

context7_key = os.environ.get("CONTEXT7_KEY", "")
if context7_key:
    mcp_servers["context7"] = {
        "command": "bunx",
        "args": ["@upstash/context7-mcp", "--api-key", context7_key],
    }
else:
    mcp_servers.pop("context7", None)

windsurf_key = os.environ.get("WINDSURF_KEY", "")
if windsurf_key:
    mcp_servers["fast-context"] = {
        "command": "bunx",
        "args": ["fast-context-mcp"],
        "enabled_tools": ["fast_context_search"],
        "env": {
            "WINDSURF_API_KEY": windsurf_key,
        },
        "tools": {
            "fast_context_search": {
                "approval_mode": "approve",
            }
        },
    }
else:
    mcp_servers.pop("fast-context", None)

if not mcp_servers:
    data.pop("mcp_servers", None)

lines: list[str] = []
write_table(lines, [], data)
result = "\n".join(line for line in lines if line is not None).rstrip() + "\n"
tmp_path = config_path.with_suffix(".toml.tmp")
tmp_path.write_text(result, encoding="utf-8")
tmp_path.replace(config_path)
PY
}

if [[ "$ENABLED_PACKAGES" == *" claude-code "* ]] && cli_available claude; then
	run_shell_allow_fail 'claude mcp remove --scope user fast-context >/dev/null 2>&1'
	run_shell_allow_fail 'claude mcp remove --scope user morph-mcp >/dev/null 2>&1'
	run_shell_allow_fail 'claude mcp remove --scope user exa >/dev/null 2>&1'
	if [[ -n "$WINDSURF_KEY" ]]; then
		run_shell_idempotent 'claude mcp add --scope user fast-context -e WINDSURF_API_KEY="$WINDSURF_KEY" -- bunx fast-context-mcp >/dev/null'
		ensure_claude_onboarding
	fi
fi

if [[ "$ENABLED_PACKAGES" == *" codex "* ]] && cli_available codex; then
	run_shell_allow_fail 'codex mcp remove fast-context >/dev/null 2>&1'
	run_shell_allow_fail 'codex mcp remove morph-mcp >/dev/null 2>&1'
	run_shell_allow_fail 'codex mcp remove exa >/dev/null 2>&1'
	run_shell_allow_fail 'codex mcp remove context7 >/dev/null 2>&1'
	if [[ -n "$CONTEXT7_KEY" ]]; then
		run_shell_idempotent 'codex mcp add context7 -- bunx @upstash/context7-mcp --api-key "$CONTEXT7_KEY" >/dev/null'
	fi
	if [[ -n "$WINDSURF_KEY" ]]; then
		run_shell_idempotent 'codex mcp add fast-context --env WINDSURF_API_KEY="$WINDSURF_KEY" -- bunx fast-context-mcp >/dev/null'
	fi
	patch_codex_mcp_config
fi
