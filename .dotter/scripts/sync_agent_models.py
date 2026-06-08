# /// script
# requires-python = ">=3.11"
# dependencies = ["tomlkit"]
# ///
"""Read current default model/provider from deployed agent configs and sync them
into .dotter/local.toml so that dotter templates use the live values."""

import json
import re
import sys
from pathlib import Path

import tomlkit


DOTTER_DIR = Path(__file__).resolve().parent.parent
LOCAL_TOML = DOTTER_DIR / 'local.toml'

PI_SETTINGS = Path.home() / '.config/pi/settings.json'
DROID_SETTINGS = Path.home() / '.factory/settings.json'
OPENCODE_CONFIG = Path.home() / '.config/opencode/opencode.jsonc'


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


def ensure_table(doc: tomlkit.TOMLDocument, *keys: str) -> tomlkit.items.Table:
    current = doc
    for key in keys:
        if key not in current:
            current.add(key, tomlkit.table())
        current = current[key]
    return current


def main() -> None:
    if LOCAL_TOML.exists():
        doc = tomlkit.parse(LOCAL_TOML.read_text())
    else:
        doc = tomlkit.document()

    changed = False

    # pi-agent: defaultModel, defaultProvider
    pi_data = read_json(PI_SETTINGS)
    if pi_data:
        pi_table = ensure_table(doc, 'variables', 'pi')
        model = pi_data.get('defaultModel', '')
        provider = pi_data.get('defaultProvider', '')
        if pi_table.get('default_model') != model:
            pi_table['default_model'] = model
            changed = True
        if pi_table.get('default_provider') != provider:
            pi_table['default_provider'] = provider
            changed = True

    # droid: sessionDefaultSettings.model
    droid_data = read_json(DROID_SETTINGS)
    if droid_data:
        droid_table = ensure_table(doc, 'variables', 'droid')
        model = droid_data.get('sessionDefaultSettings', {}).get('model', '')
        if droid_table.get('default_model') != model:
            droid_table['default_model'] = model
            changed = True

    # opencode: model
    opencode_data = read_jsonc(OPENCODE_CONFIG)
    if opencode_data:
        opencode_table = ensure_table(doc, 'variables', 'opencode')
        model = opencode_data.get('model', '')
        if opencode_table.get('default_model') != model:
            opencode_table['default_model'] = model
            changed = True

    if changed:
        LOCAL_TOML.write_text(tomlkit.dumps(doc))
        print('sync_agent_models: updated local.toml', file=sys.stderr)
    else:
        print('sync_agent_models: no changes needed', file=sys.stderr)


if __name__ == '__main__':
    main()
