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
ANTIGRAVITY_SETTINGS = agent_path('ANTIGRAVITY_CLI_HOME', Path.home() / '.config/antigravity', 'settings.json')


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


def sync_string(table: tomlkit.items.Table, key: str, value: object, fallback: str | None = None, remove_if_empty: bool = False) -> bool:
    """Sync a string value into local.toml.

    fallback: used when value is None or not a string (default: None = skip).
    remove_if_empty: if True and the final value is empty, delete the key instead.
    """
    if not isinstance(value, str):
        if fallback is None:
            return False
        value = fallback
    if isinstance(value, str) and table.get(key) == value:
        return False
    if remove_if_empty and isinstance(value, str) and not value:
        if key in table:
            del table[key]
            return True
        return False
    table[key] = value
    return True


def normalize_trusted_folders(value: object) -> list[dict[str, str]]:
    """Normalize trustedFolders dict to sorted list of {dir, trustedAt}."""
    if not isinstance(value, dict):
        return []
    result: list[dict[str, str]] = []
    for path, meta in value.items():
        if isinstance(path, str) and isinstance(meta, dict):
            trusted_at = meta.get('trustedAt')
            if isinstance(trusted_at, str):
                result.append({'dir': path, 'trustedAt': trusted_at})
    result.sort(key=lambda x: x['dir'])
    return result


def normalize_existing_trusted_folders(value: object) -> list[dict[str, str]]:
    """Normalize TOML array-of-tables to sorted list of {dir, trustedAt}."""
    if not isinstance(value, list):
        return []
    result: list[dict[str, str]] = []
    for item in value:
        if isinstance(item, dict):
            result.append({
                'dir': str(item.get('dir', '')),
                'trustedAt': str(item.get('trustedAt', '')),
            })
    result.sort(key=lambda x: x['dir'])
    return result


def sync_trusted_folders(table: tomlkit.items.Table, key: str, value: object) -> bool:
    live = normalize_trusted_folders(value)
    existing = normalize_existing_trusted_folders(table.get(key, []))
    if existing == live:
        return False

    # Build array of tables preserving TOML block style
    aot = tomlkit.aot()
    for entry in live:
        t = tomlkit.table()
        t.add('dir', entry['dir'])
        t.add('trustedAt', entry['trustedAt'])
        aot.append(t)
    table[key] = aot
    return True


def normalize_trusted_workspaces(value: object) -> list[str]:
    """Normalize trustedWorkspaces list to sorted list of strings."""
    if not isinstance(value, list):
        return []
    result = sorted(str(item) for item in value if isinstance(item, str))
    return result


def sync_trusted_workspaces(table: tomlkit.items.Table, key: str, value: object) -> bool:
    """Sync trustedWorkspaces (array of strings) into local.toml."""
    live = normalize_trusted_workspaces(value)
    existing = normalize_trusted_workspaces(table.get(key, []))
    if existing == live:
        return False
    table[key] = live
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
        changed |= sync_string(
            droid_table,
            'default_model',
            droid_data.get('sessionDefaultSettings', {}).get('model'),
            fallback='',
        )
        changed |= sync_string(droid_table, 'compaction_model', droid_data.get('compactionModel'))
        changed |= sync_int_dict(
            droid_table,
            'ide_extension_prompted_at',
            droid_data.get('ideExtensionPromptedAt', {}),
        )
        changed |= sync_trusted_folders(
            droid_table,
            'trusted_folders',
            droid_data.get('trustedFolders', {}),
        )

    # opencode: model
    opencode_data = read_jsonc(OPENCODE_CONFIG)
    if opencode_data:
        opencode_table = ensure_table(doc, 'variables', 'opencode')
        changed |= sync_string(opencode_table, 'default_model', opencode_data.get('model'))

    # codex: model, model_provider (skip empty provider to keep template guard effective)
    codex_data = read_toml(CODEX_CONFIG)
    if codex_data:
        codex_table = ensure_table(doc, 'variables', 'codex')
        changed |= sync_string(codex_table, 'default_model', codex_data.get('model'))
        changed |= sync_string(
            codex_table,
            'model_provider',
            codex_data.get('model_provider'),
            fallback='',
            remove_if_empty=True,
        )

    # antigravity: trustedWorkspaces
    antigravity_data = read_json(ANTIGRAVITY_SETTINGS)
    if antigravity_data:
        antigravity_table = ensure_table(doc, 'variables', 'antigravity')
        changed |= sync_trusted_workspaces(
            antigravity_table,
            'trusted_workspaces',
            antigravity_data.get('trustedWorkspaces', []),
        )

    if changed:
        LOCAL_TOML.write_text(tomlkit.dumps(doc))


if __name__ == '__main__':
    main()
