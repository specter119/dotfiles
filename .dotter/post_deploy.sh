#!/bin/sh
systemctl --user daemon-reload

cleanup_rendered_templates() {
	python3 - <<'PY' | while IFS= read -r file; do
import tomllib
from pathlib import Path
import re

cache_toml = Path(".dotter/cache.toml")
if not cache_toml.exists():
    raise SystemExit(0)

with cache_toml.open("rb") as fh:
    templates = tomllib.load(fh).get("templates", {})

open_tag = "{" + "{"
commented_control = re.compile(
    rf"^[ \t]*#[ \t]*{re.escape(open_tag)}[~]?(?:#|/)(?:if|each)\b",
    re.MULTILINE,
)

for source, target in templates.items():
    source_path = Path(source)
    try:
        text = source_path.read_text(encoding="utf-8")
    except (FileNotFoundError, UnicodeDecodeError):
        continue
    if not commented_control.search(text):
        continue

    print(Path(".dotter/cache") / source_path)
    print(target)
PY
		if [ -f "$file" ]; then
			sed -i '/^[[:space:]]*#[[:space:]]*$/d' "$file"
		fi
	done
}

audit_pre_commit_parser_coverage() {
	python3 - <<'PY'
import re
import tomllib
from pathlib import Path

cache_toml = Path(".dotter/cache.toml")
pre_commit_config = Path(".pre-commit-config.yaml")
if not cache_toml.exists() or not pre_commit_config.exists():
    raise SystemExit(0)

with cache_toml.open("rb") as fh:
    templates = tomllib.load(fh).get("templates", {})

open_tag = "{" + "{"
hooks_by_suffix = {
    ".json": ("check-json", "pretty-format-json"),
    ".toml": ("check-toml", "toml-sort-fix"),
    ".yaml": ("check-yaml", "yamlfmt"),
    ".yml": ("check-yaml", "yamlfmt"),
}

excludes = {}
current_hook = None
for line in pre_commit_config.read_text(encoding="utf-8").splitlines():
    hook = re.match(r"^\s*-\s+id:\s*([\w-]+)\s*$", line)
    if hook:
        current_hook = hook.group(1)
        continue
    exclude = re.match(r"^\s+exclude:\s*(.+?)\s*$", line)
    if exclude and current_hook in {
        hook for hooks in hooks_by_suffix.values() for hook in hooks
    }:
        try:
            excludes[current_hook] = re.compile(exclude.group(1))
        except re.error as error:
            print(
                f"[WARN] pre-commit coverage: invalid {current_hook} exclude regex: {error}"
            )

for source in templates:
    source_path = Path(source)
    hooks = hooks_by_suffix.get(source_path.suffix)
    if hooks is None:
        continue
    try:
        text = source_path.read_text(encoding="utf-8")
    except (FileNotFoundError, UnicodeDecodeError):
        continue
    if open_tag not in text:
        continue

    for hook in hooks:
        exclude = excludes.get(hook)
        if exclude and exclude.search(source):
            continue
        print(
            f"[WARN] pre-commit coverage: template {source} is not excluded from "
            f"{hook}; review .pre-commit-config.yaml."
        )
PY
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
audit_pre_commit_parser_coverage
normalize_glab_yaml_keys
fix_ssh_permissions
fix_glab_permissions
