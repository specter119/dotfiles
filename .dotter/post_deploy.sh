#!/bin/bash
systemctl --user daemon-reload

# Parse enabled packages from local.toml with recursive dependency resolution
parse_packages() {
	python3 - <<'PY'
import tomllib
from pathlib import Path

local_path = Path(".dotter/local.toml")
global_path = Path(".dotter/global.toml")

if not local_path.exists() or not global_path.exists():
    raise SystemExit(0)

with local_path.open("rb") as fh:
    packages = tomllib.load(fh).get("packages", [])
with global_path.open("rb") as fh:
    global_data = tomllib.load(fh)

resolved: set[str] = set()

def resolve(pkg: str) -> None:
    if pkg in resolved:
        return
    resolved.add(pkg)
    for dep in global_data.get(pkg, {}).get("depends", []):
        resolve(dep)

for pkg in packages:
    resolve(pkg)

print(" ".join(sorted(resolved)))
PY
}

ENABLED_PACKAGES=" $(parse_packages) "

# Share opencode plugins: link opencode-cn -> opencode
# See: https://github.com/SuperCuber/dotter/issues/186
if [[ "$ENABLED_PACKAGES" == *" opencode-cn "* ]]; then
	ln -sfn ~/.config/opencode/plugins ~/.config/opencode-cn/plugins
	ln -sfn ~/.config/opencode/AGENTS.md ~/.config/opencode-cn/
else
	rm -rf ~/.config/opencode-cn
fi

# Configure Claude Code MCP servers and onboarding flag
if [[ "$ENABLED_PACKAGES" == *" claude-code "* ]]; then
	MORPH_KEY=$(rbw get morph-api-key 2>/dev/null)
	EXA_KEY=$(rbw get exa-api-key 2>/dev/null)

	if [[ -n "$MORPH_KEY" && -n "$EXA_KEY" ]]; then
		claude mcp remove --scope user morph-mcp &>/dev/null || true
		claude mcp add --scope user morph-mcp \
			-e "MORPH_API_KEY=$MORPH_KEY" \
			-e ENABLED_TOOLS=edit_file,warpgrep_codebase_search \
			-- bunx -y @morphllm/morphmcp >/dev/null
		claude mcp remove --scope user exa &>/dev/null || true
		claude mcp add --scope user exa \
			-e "EXA_API_KEY=$EXA_KEY" \
			-- bunx -y exa-mcp-server \
			"tools=web_search_exa,get_code_context_exa,crawling_exa" >/dev/null

		# Ensure hasCompletedOnboarding is set
		CLAUDE_JSON="$HOME/.claude.json"
		if [[ -f "$CLAUDE_JSON" ]] && ! jq -e '.hasCompletedOnboarding == true' "$CLAUDE_JSON" >/dev/null 2>&1; then
			_tmp=$(jq '.hasCompletedOnboarding = true' "$CLAUDE_JSON") && printf '%s\n' "$_tmp" >"$CLAUDE_JSON"
			unset _tmp
		fi
	fi
fi
