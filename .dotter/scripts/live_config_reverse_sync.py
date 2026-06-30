# /// script
# requires-python = ">=3.11"
# dependencies = ["tomlkit"]
# ///
"""Read current local state from deployed agent configs and sync it
into .dotter/local.toml so that dotter templates use the live values."""

import json
import os
import re
from pathlib import Path

import tomlkit
from tomlkit.exceptions import ParseError


DOTTER_DIR = Path(__file__).resolve().parent.parent
LOCAL_TOML = DOTTER_DIR / 'local.toml'


def expand_path(value: str | Path) -> Path:
    return Path(os.path.expanduser(os.path.expandvars(str(value))))


def agent_path(env_name: str, fallback: str | Path, *parts: str) -> Path:
    raw = os.environ.get(env_name) or str(fallback)
    return expand_path(raw).joinpath(*parts)


XDG_CONFIG_HOME = expand_path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
PI_SETTINGS = agent_path('PI_CODING_AGENT_DIR', Path.home() / '.pi', 'settings.json')
DROID_SETTINGS = Path.home() / '.factory/settings.json'
OPENCODE_CONFIG = XDG_CONFIG_HOME / 'opencode' / 'opencode.jsonc'
CODEX_CONFIG = agent_path('CODEX_HOME', Path.home() / '.codex', 'config.toml')
COPILOT_SETTINGS = agent_path('COPILOT_HOME', Path.home() / '.copilot', 'settings.json')


def read_json(path: Path) -> dict | None:
    """Read JSON from path, resolving symlinks to skip repo source templates."""
    if not path.exists():
        return None
    real = path.resolve()
    # If symlinked back to repo source, the file has raw template syntax
    if str(DOTTER_DIR.parent) in str(real):
        return None
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return None


def read_jsonc(path: Path) -> dict | None:
    """Read JSONC (JSON with comments) from path, stripping // comments."""
    if not path.exists():
        return None
    real = path.resolve()
    if str(DOTTER_DIR.parent) in str(real):
        return None
    try:
        text = path.read_text()
        lines = [l for l in text.splitlines() if not re.match(r'^\s*//', l)]
        return json.loads('\n'.join(lines))
    except (json.JSONDecodeError, OSError):
        return None


def read_toml(path: Path) -> tomlkit.TOMLDocument | None:
    """Read TOML from path, resolving symlinks to skip repo source templates."""
    if not path.exists():
        return None
    real = path.resolve()
    if str(DOTTER_DIR.parent) in str(real):
        return None
    try:
        return tomlkit.parse(path.read_text())
    except (ParseError, OSError):
        return None


def ensure_table(doc: tomlkit.TOMLDocument, *keys: str) -> tomlkit.items.Table:
    current = doc
    for key in keys:
        if key not in current:
            current.add(key, tomlkit.table())
        current = current[key]
    return current


def sync_string(table: tomlkit.items.Table, key: str, value: object) -> bool:
    if not isinstance(value, str):
        return False
    if table.get(key) == value:
        return False
    table[key] = value
    return True


def normalize_int_dict(value: object) -> dict[str, int]:
    if not isinstance(value, dict):
        return {}
    result: dict[str, int] = {}
    for key, item in value.items():
        if isinstance(key, str) and isinstance(item, int) and not isinstance(item, bool):
            result[key] = item
    return result


def sync_int_dict(table: tomlkit.items.Table, key: str, value: object) -> bool:
    normalized = normalize_int_dict(value)
    existing = normalize_int_dict(table.get(key, {}))
    if existing == normalized:
        return False

    inline = tomlkit.inline_table()
    for item_key, item_value in normalized.items():
        inline[item_key] = item_value
    table[key] = inline
    return True


def main() -> None:
    if LOCAL_TOML.exists():
        doc = tomlkit.parse(LOCAL_TOML.read_text())
    else:
        doc = tomlkit.document()

    changed = False

    # pi-agent: defaultModel, defaultProvider, lastChangelogVersion
    pi_data = read_json(PI_SETTINGS)
    if pi_data:
        pi_table = ensure_table(doc, 'variables', 'pi')
        changed |= sync_string(pi_table, 'default_model', pi_data.get('defaultModel'))
        changed |= sync_string(pi_table, 'default_provider', pi_data.get('defaultProvider'))
        changed |= sync_string(
            pi_table,
            'last_changelog_version',
            pi_data.get('lastChangelogVersion'),
        )

    # droid: sessionDefaultSettings.model
    droid_data = read_json(DROID_SETTINGS)
    if droid_data:
        droid_table = ensure_table(doc, 'variables', 'droid')
        model = droid_data.get('sessionDefaultSettings', {}).get('model', '')
        if droid_table.get('default_model') != model:
            droid_table['default_model'] = model
            changed = True
        changed |= sync_string(droid_table, 'compaction_model', droid_data.get('compactionModel'))
        changed |= sync_int_dict(
            droid_table,
            'ide_extension_prompted_at',
            droid_data.get('ideExtensionPromptedAt', {}),
        )

    # opencode: model
    opencode_data = read_jsonc(OPENCODE_CONFIG)
    if opencode_data:
        opencode_table = ensure_table(doc, 'variables', 'opencode')
        model = opencode_data.get('model', '')
        if opencode_table.get('default_model') != model:
            opencode_table['default_model'] = model
            changed = True

    # codex: model, model_provider (skip empty provider to keep template guard effective)
    codex_data = read_toml(CODEX_CONFIG)
    if codex_data:
        codex_table = ensure_table(doc, 'variables', 'codex')
        changed |= sync_string(codex_table, 'default_model', codex_data.get('model'))
        provider = codex_data.get('model_provider', '')
        if provider:
            changed |= sync_string(codex_table, 'model_provider', provider)
        elif codex_table.get('model_provider'):
            # remove stale empty provider from local.toml
            del codex_table['model_provider']
            changed = True

    # copilot: model
    copilot_data = read_json(COPILOT_SETTINGS)
    if copilot_data:
        copilot_table = ensure_table(doc, 'variables', 'copilot')
        changed |= sync_string(copilot_table, 'default_model', copilot_data.get('model'))

    if changed:
        LOCAL_TOML.write_text(tomlkit.dumps(doc))


if __name__ == '__main__':
    main()
