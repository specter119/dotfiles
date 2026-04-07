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

cleanup_rendered_yaml_templates() {
	python3 - <<'PY' | while IFS= read -r file; do
import tomllib
from pathlib import Path

cache_toml = Path(".dotter/cache.toml")
if not cache_toml.exists():
    raise SystemExit(0)

with cache_toml.open("rb") as fh:
    templates = tomllib.load(fh).get("templates", {})

for source, target in templates.items():
    source_path = Path(source)
    if source_path.suffix not in {".yaml", ".yml"}:
        continue
    try:
        text = source_path.read_text(encoding="utf-8")
    except (FileNotFoundError, UnicodeDecodeError):
        continue
    if "{" + "{" not in text:
        continue

    print(Path(".dotter/cache") / source_path)
    print(target)
PY
		if [[ -f "$file" ]]; then
			sed -i '/^[[:space:]]*#[[:space:]]*$/d' "$file"
		fi
	done
}

# Shared MCP secrets (do not depend on enabled packages)
MORPH_KEY=$(rbw get morph-api-key 2>/dev/null)
CONTEXT7_KEY=$(rbw get context7-api-key 2>/dev/null)
export MORPH_KEY CONTEXT7_KEY

# Clean legacy standalone opencode-cn config after merging back into opencode.
rm -rf ~/.config/opencode-cn

# Clean up rendered YAML templates after deployment.
cleanup_rendered_yaml_templates

# Configure MCP servers for agentic CLIs
bash .dotter/scripts/mcp_setup.sh --shell fish
