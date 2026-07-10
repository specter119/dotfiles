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
    if source_path.suffix not in {".yaml", ".yml", ".toml", ".json", ".md"}:
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

normalize_glab_yaml_keys() {
	python3 - <<'PY'
from pathlib import Path
import re

paths = [
    Path.home() / ".config/glab-cli/config.yml",
    Path(".dotter/cache/glab/config.yml"),
]

for path in paths:
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    normalized = re.sub(r'^([ \t]*)"([^"\n]+)":', r'\1\2:', text, flags=re.MULTILINE)
    normalized = re.sub(r'^host: "([^"\n]+)"$', r'host: \1', normalized, flags=re.MULTILINE)
    normalized = re.sub(
        r'^last_update_check_timestamp: "([^"\n]+)"$',
        r'last_update_check_timestamp: \1',
        normalized,
        flags=re.MULTILINE,
    )
    normalized = re.sub(
        r'^last_seen_version: "([^"\n]+)"$',
        r'last_seen_version: \1',
        normalized,
        flags=re.MULTILINE,
    )
    normalized = re.sub(
        r'^(\s+)(?!token:)([A-Za-z_]+): "([^"\n]+)"$',
        r'\1\2: \3',
        normalized,
        flags=re.MULTILINE,
    )
    if normalized != text:
        path.write_text(normalized, encoding="utf-8")
PY
}

fix_ssh_permissions() {
	if [ -d "$HOME/.ssh" ]; then
		chmod 700 "$HOME/.ssh" 2>/dev/null || true
	fi
	if [ -f "$HOME/.ssh/config" ]; then
		chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
	fi
	if [ -d "$HOME/.ssh/config.d" ]; then
		chmod 700 "$HOME/.ssh/config.d" 2>/dev/null || true
		find "$HOME/.ssh/config.d" -maxdepth 1 -type f -exec chmod 600 {} \; 2>/dev/null || true
	fi
}

fix_glab_permissions() {
	if [ -d "$HOME/.config/glab-cli" ]; then
		for file in "$HOME/.config/glab-cli"/*; do
			if [ -f "$file" ]; then
				chmod 600 "$file" 2>/dev/null || true
			fi
		done
	fi
}

# Clean up rendered templates (YAML, TOML, JSON and Markdown) after deployment.
cleanup_rendered_templates
normalize_glab_yaml_keys
fix_ssh_permissions
fix_glab_permissions
