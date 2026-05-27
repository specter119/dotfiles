#!/bin/sh
systemctl --user daemon-reload

cleanup_rendered_templates() {
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
    if source_path.suffix not in {".yaml", ".yml", ".toml"}:
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
		if [ -f "$file" ]; then
			sed -i '/^[[:space:]]*#[[:space:]]*$/d' "$file"
		fi
	done
}

# Clean up rendered templates (YAML and TOML) after deployment.
cleanup_rendered_templates
