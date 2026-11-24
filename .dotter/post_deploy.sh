#!/bin/sh
systemctl --user daemon-reload

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

fix_rclone_permissions() {
	if [ -f "$HOME/.config/rclone/rclone.conf" ]; then
		chmod 600 "$HOME/.config/rclone/rclone.conf" 2>/dev/null || true
	fi
}

fix_magpie_env_permissions() {
	env_file="$HOME/.config/environment.d/magpie.conf"
	if [ -f "$env_file" ]; then
		chmod 600 "$env_file" 2>/dev/null || true
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
import os
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request

config, version, out = sys.argv[1:4]
with open(config, "rb") as fh:
    provider = tomllib.load(fh).get("model_providers", {}).get("magpie", {})
base = urllib.parse.urlsplit(provider.get("base_url", ""))
key_env = provider.get("env_key", "")
token = os.environ.get(key_env, "") if key_env else provider.get("experimental_bearer_token", "")
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
# Codex only turns on Code Mode for models whose catalog entry declares
# `tool_mode`; the gateway does not emit it, so declare it here. These families
# passed a code-mode-only probe, where every tool call goes through the exec
# surface; the rest keep direct tools available alongside Code Mode.
code_mode_only_families = ("deepseek", "glm", "zai-glm", "kimi", "gemini", "qwen3.8-max")


def code_mode_only(slug):
    name = slug.split("/", 1)[-1]
    if name.startswith(code_mode_only_families):
        return True
    if name.startswith("gpt-"):
        try:
            return int(name.split("-")[1].split(".")[0]) >= 5
        except ValueError:
            return False
    return False


for model in catalog["models"]:
    mode = "code_mode_only" if code_mode_only(model["slug"]) else "code_mode"
    model.setdefault("tool_mode", mode)
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

# Pi reads its model list from ~/.config/pi/models.json. Build it straight from
# the gateway's /v1/models, the way the Codex catalog is built, instead of
# driving `magpie pi`: the host CLI's catalog lags the container gateway, so it
# drops models the gateway already serves. The gateway owns the model facts;
# cost, promptCache and compat survive from the previous file when the id is
# unchanged. The gateway accepts /v1/responses for every model and converts it
# for chat-only upstreams (Codex relies on this), so the whole magpie provider
# uses openai-responses.
refresh_magpie_pi_models() {
	models="$HOME/.config/pi/models.json"
	[ -f "$models" ] || return 0
	if python3 - "$models" "$models.tmp" <<'PY'
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

src, out = sys.argv[1:3]
with open(src, encoding="utf-8") as fh:
    data = json.load(fh)
provider = data.get("providers", {}).get("magpie")
if provider is None:
    sys.exit(1)

def gateway_catalog():
    auth_path = Path.home() / ".config/pi/auth.json"
    token = ""
    if auth_path.is_file():
        magpie = json.loads(auth_path.read_text(encoding="utf-8")).get("magpie") or {}
        token = magpie.get("key") or magpie.get("apiKey") or ""
    base = provider.get("baseUrl") or "http://127.0.0.1:3425/v1"
    if not token:
        raise RuntimeError("no magpie key")
    url = base.rstrip("/") + "/models"
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request, timeout=10) as response:
        catalog = json.load(response)
    entries = [
        item
        for item in catalog.get("data") or []
        if isinstance(item, dict) and item.get("id")
    ]
    if not entries:
        raise RuntimeError("empty catalog")
    return entries

LEVELS = ("minimal", "low", "medium", "high", "xhigh", "max", "off")

def thinking_level_map(entry):
    levels = []
    for item in entry.get("reasoning_levels") or []:
        effort = item.get("effort") if isinstance(item, dict) else item
        if effort:
            levels.append(str(effort))
    if not levels:
        return None
    return {level: level if level in levels else None for level in LEVELS}

previous = {
    model.get("id"): model
    for model in provider.get("models", [])
    if isinstance(model, dict)
}
built = []
for entry in gateway_catalog():
    model_id = entry["id"]
    model = dict(previous.get(model_id) or {})
    model["id"] = model_id
    model["name"] = (
        entry.get("magpie_label")
        or entry.get("display_name")
        or model.get("name")
        or model_id
    )
    window = entry.get("context_window") or entry.get("context_length")
    if window:
        model["contextWindow"] = window
    if entry.get("max_output_tokens"):
        model["maxTokens"] = entry["max_output_tokens"]
    inputs = [
        modality
        for modality in (entry.get("modalities") or {}).get("input") or []
        if modality in ("text", "image")
    ]
    if inputs:
        model["input"] = inputs
    model["reasoning"] = bool(entry.get("reasoning"))
    level_map = thinking_level_map(entry)
    if model["reasoning"] and level_map:
        model["thinkingLevelMap"] = level_map
    model.pop("api", None)
    model.setdefault("compat", {"supportsStrictMode": True})
    built.append(model)

provider["api"] = "openai-responses"
provider["models"] = built

with open(out, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write("\n")
PY
	then
		mv "$models.tmp" "$models"
	else
		rm -f "$models.tmp"
		echo "[WARN] magpie pi models.json refresh failed; keeping the existing file"
	fi
}

# Magpie reads its settings.json while it runs, and Dotter writes templates in place
# (truncate, then write). Re-publish the file with a rename afterwards, so the next read
# sees a complete file instead of falling back to settings.json.bak.
republish_magpie_settings() {
	dir="${XDG_CONFIG_HOME:-$HOME/.config}/magpie"
	[ -f "$dir/settings.json" ] || return 0
	cp "$dir/settings.json" "$dir/.settings.json.tmp" &&
		mv "$dir/.settings.json.tmp" "$dir/settings.json"
}

# dsh's model list lives in its profile patch, which only `magpie dsh <model>` writes.
# Re-apply the model from local.toml, then put the provider back on magpie's Anthropic
# wire: magpie owns the models, the wire is ours.
refresh_magpie_dsh_models() {
	command -v magpie >/dev/null 2>&1 || return 0
	[ -f .dotter/local.toml ] || return 0

	model=$(python3 - <<'PY'
import tomllib

with open(".dotter/local.toml", "rb") as fh:
    dsh = tomllib.load(fh).get("variables", {}).get("dsh", {})
print(dsh.get("default_model", ""))
PY
	)
	[ -n "$model" ] || return 0

	if ! magpie dsh "$model" >/dev/null 2>&1; then
		echo "[WARN] magpie dsh $model failed; keeping the existing dsh profile patch"
		return 0
	fi

	python3 - "${DSH_HOME:-$HOME/.dsh}/profiles/web/cordis.patch.yml" <<'PATCH'
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(0)

original = path.read_text(encoding="utf-8")
out = []
in_entry = False
provider = ""
for line in original.splitlines():
    stripped = line.strip()
    if stripped.startswith("- id:"):
        in_entry = stripped.split(":", 1)[1].strip() == "llm-pi-ai"
        provider = ""
    elif in_entry and line.startswith("      ") and not line.startswith("       ") and stripped.endswith(":"):
        provider = stripped[:-1]
    elif in_entry and provider == "magpie" and line.startswith("        api: "):
        line = "        api: anthropic-messages"
    elif in_entry and provider == "magpie" and line.startswith("        baseURL: "):
        line = "        baseURL: http://127.0.0.1:3425"
    out.append(line)

text = "\n".join(out) + "\n"
if text != original:
    path.write_text(text, encoding="utf-8")
PATCH
}

refresh_magpie_codex_catalog
refresh_magpie_pi_models
refresh_magpie_dsh_models
republish_magpie_settings
audit_prek_parser_coverage
fix_ssh_permissions
fix_glab_permissions
fix_rclone_permissions
fix_magpie_env_permissions
