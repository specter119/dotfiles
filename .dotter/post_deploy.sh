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

audit_prek_parser_coverage() {
	python3 - <<'PY'
import re
import tomllib
from pathlib import Path

cache_toml = Path(".dotter/cache.toml")
prek_config = Path("prek.toml")
if not cache_toml.exists() or not prek_config.exists():
    raise SystemExit(0)

with cache_toml.open("rb") as fh:
    templates = tomllib.load(fh).get("templates", {})

open_tag = "{" + "{"
hooks_by_suffix = {
    ".json": ("check-json", "pretty-format-json"),
    ".toml": ("check-toml", "toml-sort-fix"),
    ".yaml": ("check-yaml",),
    ".yml": ("check-yaml",),
}
known_hooks = {hook for hooks in hooks_by_suffix.values() for hook in hooks}
configured_excludes = {}
with prek_config.open("rb") as fh:
    config = tomllib.load(fh)
for repo in config.get("repos", []):
    for hook_config in repo.get("hooks", []):
        hook = hook_config.get("id")
        if hook not in known_hooks:
            continue
        exclude = None
        raw_exclude = hook_config.get("exclude")
        if raw_exclude is not None:
            try:
                exclude = re.compile(raw_exclude)
            except re.error as error:
                print(
                    f"[WARN] prek coverage: invalid {hook} exclude regex: {error}"
                )
        configured_excludes.setdefault(hook, []).append(exclude)

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
        excludes = configured_excludes.get(hook)
        if not excludes:
            continue
        if all(exclude is not None and exclude.search(source) for exclude in excludes):
            continue
        print(
            f"[WARN] prek coverage: template {source} is not excluded from "
            f"{hook}; review prek.toml."
        )
PY
}

fix_ssh_permissions() {
	if [ -d "$HOME/.ssh" ]; then
		chmod 700 "$HOME/.ssh" 2>/dev/null || true
	fi
	if [ -f "$HOME/.ssh/config" ]; then
		chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
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

# Codex wants its model catalog as a file. The magpie gateway serves it in
# Codex's own format on /v1/codex/models, so fetch it from there instead of
# driving `magpie codex`, which rewrites config.toml and stash.json. The older
# /backend-api/codex/models route is now proxied to ChatGPT and rejects the
# magpie key with 401.
refresh_magpie_codex_catalog() {
	config="$HOME/.config/codex/config.toml"
	[ -f "$config" ] || return 0
	grep -q '^model_catalog_json = "magpie-models.json"' "$config" || return 0
	command -v codex >/dev/null 2>&1 || return 0
	version=$(codex --version 2>/dev/null | awk '{print $NF}')
	[ -n "$version" ] || return 0

	out=$(mktemp) || return 0
	if python3 - "$config" "$version" "$out" <<'PY'
import json
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request

config, version, out = sys.argv[1:4]
with open(config, "rb") as fh:
    provider = tomllib.load(fh).get("model_providers", {}).get("magpie", {})
base = urllib.parse.urlsplit(provider.get("base_url", ""))
token = provider.get("experimental_bearer_token", "")
if not base.scheme or not token:
    raise SystemExit(1)
url = f"{base.scheme}://{base.netloc}/v1/codex/models?client_version={version}"
request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
try:
    with urllib.request.urlopen(request, timeout=10) as response:
        catalog = json.load(response)
except (urllib.error.URLError, OSError, ValueError):
    raise SystemExit(1)
if not catalog.get("models"):
    raise SystemExit(1)
with open(out, "w", encoding="utf-8") as fh:
    json.dump(catalog, fh, ensure_ascii=False)
PY
	then
		mv "$out" "$HOME/.config/codex/magpie-models.json"
	else
		rm -f "$out"
		echo "[WARN] magpie codex catalog refresh failed; keeping the existing catalog"
	fi
}

# magpie labels each model with its upstream's native wire, so models.json mixes
# openai-completions and openai-responses. The gateway accepts /v1/responses for
# every model and converts it for chat-only upstreams (Codex relies on this), so
# make the whole magpie provider use openai-responses. magpie rewrites the file
# on every `magpie pi` run, hence this runs after each refresh.
force_pi_models_responses() {
	models="$HOME/.config/pi/models.json"
	[ -f "$models" ] || return 0
	if python3 - "$models" "$models.tmp" <<'PY'
import json
import sys

src, out = sys.argv[1:3]
with open(src, encoding="utf-8") as fh:
    data = json.load(fh)
provider = data.get("providers", {}).get("magpie")
if provider is None:
    sys.exit(1)
provider["api"] = "openai-responses"
for model in provider.get("models", []):
    model.pop("api", None)
with open(out, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write("\n")
PY
	then
		mv "$models.tmp" "$models"
	else
		rm -f "$models.tmp"
		echo "[WARN] forcing pi models.json to openai-responses failed; keeping the magpie-generated file"
	fi
}
# Pi reads its model list from ~/.config/pi/models.json, which only
# `magpie pi <model>` writes. Re-apply the model Dotter just rendered into
# settings.json: the values are identical, so settings.json stays byte-equal to
# the Dotter cache and only models.json is refreshed.
refresh_magpie_pi_models() {
	command -v magpie >/dev/null 2>&1 || return 0
	[ -f .dotter/local.toml ] || return 0

	model=$(python3 - <<'PY'
import tomllib

with open(".dotter/local.toml", "rb") as fh:
    pi = tomllib.load(fh).get("variables", {}).get("pi", {})
if pi.get("default_provider") == "magpie":
    print(pi.get("default_model", ""))
PY
	)
	[ -n "$model" ] || return 0

	if magpie pi "$model" >/dev/null 2>&1; then
		force_pi_models_responses
	else
		echo "[WARN] magpie pi $model failed; keeping the existing pi models.json"
	fi
}

# Clean up rendered templates (YAML, TOML, JSON and Markdown) after deployment.
cleanup_rendered_templates
refresh_magpie_codex_catalog
refresh_magpie_pi_models
audit_prek_parser_coverage
fix_ssh_permissions
fix_glab_permissions
