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

# Parse a variable from local.toml with a default fallback
parse_variable() {
	local key="$1" default="$2"
	python3 - "$key" "$default" <<'PY'
import sys, tomllib
from pathlib import Path

key, default = sys.argv[1], sys.argv[2]
local_path = Path(".dotter/local.toml")
if local_path.exists():
    with local_path.open("rb") as fh:
        val = tomllib.load(fh).get("variables", {}).get(key, default)
else:
    val = default
print(val)
PY
}

DOMAIN=$(parse_variable domain homelab.com)
export DOMAIN

# Shared MCP secrets (do not depend on enabled packages)
MORPH_KEY=$(rbw get morph-api-key 2>/dev/null)
EXA_KEY=$(rbw get exa-api-key 2>/dev/null)
CONTEXT7_KEY=$(rbw get context7-api-key 2>/dev/null)
export MORPH_KEY EXA_KEY CONTEXT7_KEY

# Share opencode plugins: link opencode-cn -> opencode
# See: https://github.com/SuperCuber/dotter/issues/186
if [[ "$ENABLED_PACKAGES" == *" opencode-cn "* ]]; then
	ln -sfn ~/.config/opencode/plugins ~/.config/opencode-cn/plugins
	ln -sfn ~/.config/opencode/AGENTS.md ~/.config/opencode-cn/
else
	rm -rf ~/.config/opencode-cn
fi

# Configure MCP servers for agentic CLIs
bash .dotter/scripts/mcp_setup.sh --shell fish
