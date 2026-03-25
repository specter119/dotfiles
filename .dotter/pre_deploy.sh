#!/bin/bash
rbw sync

ensure_git_enterprise_table() {
	python3 - <<'PY'
import tomllib
from pathlib import Path

path = Path(".dotter/local.toml")
if not path.exists():
    raise SystemExit(0)

text = path.read_text(encoding="utf-8")
data = tomllib.loads(text)
variables = data.get("variables", {})

needs_enterprise_table = "git_enterprise" not in variables
if not needs_enterprise_table:
    raise SystemExit(0)

added: list[str] = []
with path.open("a", encoding="utf-8") as fh:
    if "variables" not in data:
        fh.write("\n[variables]\n")
    if needs_enterprise_table:
        fh.write("\n[variables.git_enterprise]\n")
        added.append("git_enterprise")

print(f"[pre-deploy] Added missing tables to {path}: {', '.join(added)}")
PY
}

ensure_git_enterprise_table

python3 .dotter/scripts/render_git_enterprise.py generate
