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
if not missing:
    raise SystemExit(0)

with path.open("a", encoding="utf-8") as fh:
    if "variables" not in data:
        fh.write("\n[variables]\n")
    for key, value in missing.items():
        fh.write(f"{key} = {value}\n")

names = ", ".join(missing)
print(f"[pre-deploy] Added default variables to {path}: {names}")
PY
}

ensure_variables
