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
