#!/bin/bash
systemctl --user daemon-reload

# Parse enabled packages from local.toml
parse_packages() {
  python3 - <<'PY'
import tomllib
from pathlib import Path

path = Path(".dotter/local.toml")
if not path.exists():
    raise SystemExit(0)
with path.open("rb") as fh:
    data = tomllib.load(fh)
packages = data.get("packages", [])
if isinstance(packages, list):
    print(" ".join(str(p) for p in packages))
PY
}

ENABLED_PACKAGES=" $(parse_packages) "

# Share opencode plugins: link opencode-cn -> opencode
# See: https://github.com/SuperCuber/dotter/issues/186
if [[ "$ENABLED_PACKAGES" == *" opencode-cn "* ]]; then
  ln -sfn ~/.config/opencode/plugins ~/.config/opencode-cn/plugins
fi
