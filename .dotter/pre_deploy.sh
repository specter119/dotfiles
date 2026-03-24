#!/bin/bash
rbw sync

ensure_variables() {
	python3 - <<'PY'
import tomllib
from pathlib import Path

path = Path(".dotter/local.toml")
if not path.exists():
    raise SystemExit(0)

text = path.read_text(encoding="utf-8")
data = tomllib.loads(text)
variables = data.get("variables", {})

defaults = {
    "domain": '"homelab.com"',
}

missing = {k: v for k, v in defaults.items() if k not in variables}
needs_enterprise_table = "git_enterprise" not in variables
if not missing and not needs_enterprise_table:
    raise SystemExit(0)

added: list[str] = []
with path.open("a", encoding="utf-8") as fh:
    if "variables" not in data:
        fh.write("\n[variables]\n")
    for key, value in missing.items():
        fh.write(f"{key} = {value}\n")
        added.append(key)
    if needs_enterprise_table:
        fh.write("\n[variables.git_enterprise]\n")
        added.append("git_enterprise")

print(f"[pre-deploy] Added default variables to {path}: {', '.join(added)}")
PY
}

ensure_variables

python3 .dotter/scripts/render_git_enterprise.py generate
