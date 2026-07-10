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
GLAB_CONFIG = XDG_CONFIG_HOME / 'glab-cli' / 'config.yml'
SSH_CONFIG_D = Path.home() / '.ssh' / 'config.d'


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


def parse_glab_scalar_value(value: str) -> str:
    value = value.strip()
    if value.startswith('!!null '):
        value = value.removeprefix('!!null ').strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return value
    return value


def parse_glab_timestamp_value(value: str) -> str:
    value = value.strip()
    if value.startswith('!!null '):
        return f'!!null {parse_glab_scalar_value(value)}'
    return parse_glab_scalar_value(value)


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


def _is_live_file(path: Path) -> bool:
    """Check that a file exists and is not symlinked back to repo source."""
    if not path.exists():
        return False
    real = path.resolve()
    return str(DOTTER_DIR.parent) not in str(real)


def _parse_glab_hosts(filepath: Path) -> dict[str, dict[str, str]] | None:
    """Extract all host fields from live glab config.yml.

    Returns dict keyed by hostname, each value is a dict of field-name -> field-value.
    """
    if not _is_live_file(filepath):
        return None
    text = filepath.read_text()
    result: dict[str, dict[str, str]] = {}
    current_host: str | None = None
    current_host_indent: int | None = None
    in_hosts = False
    for line in text.splitlines():
        stripped = line.rstrip()
        indent = len(stripped) - len(stripped.lstrip(' '))
        content = stripped.lstrip(' ')
        if not in_hosts:
            if re.match(r'^hosts:\s*', stripped):
                in_hosts = True
            continue
        # End of hosts section: non-indented non-comment non-empty line
        if content and indent == 0 and not content.startswith('#'):
            break
        if not content or content.startswith('#'):
            continue
        # Host block start: indented key colon
        if indent > 0 and content.endswith(':'):
            current_host = parse_glab_scalar_value(content.removesuffix(':'))
            current_host_indent = indent
            result[current_host] = {}
            continue
        # Host field: deeper indent under current host
        if current_host and current_host_indent is not None and indent > current_host_indent:
            kv_match = re.match(r'^([^:]+):\s*(.*)$', content)
            if kv_match:
                key = parse_glab_scalar_value(kv_match.group(1).strip())
                value = parse_glab_scalar_value(kv_match.group(2).strip())
                result[current_host][key] = value
    return result


def normalize_glab_hosts(
    value: object,
) -> list[tuple[str, tuple[tuple[str, str], ...]]]:
    """Normalize glab hosts while preserving non-host field order and raw values."""
    if not isinstance(value, dict):
        return []
    result: list[tuple[str, tuple[tuple[str, str], ...]]] = []
    for host, fields in value.items():
        if not isinstance(host, str) or not isinstance(fields, dict):
            continue
        normalized_fields: list[tuple[str, str]] = []
        for key, item in fields.items():
            if isinstance(key, str) and key != 'host' and isinstance(item, str):
                normalized_fields.append((key, item))
        result.append((host, tuple(normalized_fields)))
    result.sort(key=lambda x: x[0])
    return result


def normalize_existing_glab_hosts(
    value: object,
) -> list[tuple[str, tuple[tuple[str, str], ...]]]:
    """Normalize TOML glab host entries while preserving field order."""
    if not isinstance(value, list):
        return []
    result: list[tuple[str, tuple[tuple[str, str], ...]]] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        host = item.get('host')
        if not isinstance(host, str) or not host:
            continue
        normalized_fields: list[tuple[str, str]] = []
        for key, item_value in item.items():
            if isinstance(key, str) and key != 'host' and isinstance(item_value, str):
                normalized_fields.append((key, item_value))
        result.append((host, tuple(normalized_fields)))
    result.sort(key=lambda x: x[0])
    return result


def sync_glab_hosts(table: tomlkit.items.Table, key: str, value: object) -> bool:
    """Sync glab hosts into local.toml as array-of-tables."""
    live = normalize_glab_hosts(value)
    existing = normalize_existing_glab_hosts(table.get(key, []))
    if not live and existing:
        return False
    if existing == live:
        return False

    aot = tomlkit.aot()
    for host, fields in live:
        host_table = tomlkit.table()
        host_table.add('host', host)
        for field, field_value in fields:
            host_table.add(field, field_value)
        aot.append(host_table)
    table[key] = aot
    return True


def sync_glab_config(doc: tomlkit.TOMLDocument) -> bool:
    """Reverse-sync glab runtime state and host fields from live config."""
    if not _is_live_file(GLAB_CONFIG):
        return False
    text = GLAB_CONFIG.read_text()

    ts_match = re.search(r'^last_update_check_timestamp:\s*(.+)$', text, re.MULTILINE)
    ts = parse_glab_timestamp_value(ts_match.group(1)) if ts_match else ''

    host_match = re.search(r'^host:\s*(.+)$', text, re.MULTILINE)
    default_host = parse_glab_scalar_value(host_match.group(1)) if host_match else ''

    ver_match = re.search(r'^last_seen_version:\s*(.+)$', text, re.MULTILINE)
    ver = parse_glab_scalar_value(ver_match.group(1)) if ver_match else ''

    glab_table = ensure_table(doc, 'variables', 'glab')
    changed = False
    changed |= sync_string(glab_table, 'default_host', default_host)
    changed |= sync_string(glab_table, 'last_update_check_timestamp', ts)
    changed |= sync_string(glab_table, 'last_seen_version', ver)
    changed |= sync_glab_hosts(glab_table, 'hosts', _parse_glab_hosts(GLAB_CONFIG) or {})
    return changed


def normalize_ssh_hosts(value: object) -> list[dict[str, str]]:
    """Normalize TOML array-of-tables to sorted list of {alias, hostname}."""
    if not isinstance(value, list):
        return []
    result = [
        {'alias': str(item.get('alias', '')), 'hostname': str(item.get('hostname', ''))}
        for item in value
        if isinstance(item, dict)
    ]
    result.sort(key=lambda x: x['alias'])
    return result


def parse_ssh_config_site(filepath: Path, site_name: str) -> dict | None:
    """Parse an ssh config.d file for a site.

    Extracts:
    - user: from wildcard 'Host <site>_*' block's User directive
    - hosts: from specific 'Host <site>_<alias>' blocks with HostName directives

    Returns {user: str, hosts: [{alias, hostname}]} or None.
    """
    if not _is_live_file(filepath):
        return None
    content = filepath.read_text()
    if not content.strip():
        return None

    user = ''
    hosts: list[dict[str, str]] = []
    wildcard_pattern = f'{site_name}_*'

    # Parse into Host blocks
    blocks: dict[str, dict[str, str]] = {}
    current_host: str | None = None
    current_directives: dict[str, str] = {}

    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        host_match = re.match(r'^Host\s+(.+)$', stripped, re.IGNORECASE)
        if host_match:
            if current_host is not None:
                blocks[current_host] = current_directives
            current_host = host_match.group(1).strip()
            current_directives = {}
            continue
        kv_match = re.match(r'^(\w+)\s*[= ]\s*(.+)$', stripped, re.IGNORECASE)
        if kv_match and current_host is not None:
            current_directives[kv_match.group(1)] = kv_match.group(2).strip()

    if current_host is not None:
        blocks[current_host] = current_directives

    # User from wildcard block
    if wildcard_pattern in blocks:
        user = blocks[wildcard_pattern].get('User', '')

    # Specific hosts
    prefix = f'{site_name}_'
    host_users: list[str] = []
    for host_pattern, directives in blocks.items():
        if host_pattern == wildcard_pattern:
            continue
        if host_pattern.startswith(prefix):
            alias = host_pattern[len(prefix):]
            hostname = directives.get('HostName', '')
            host_user = directives.get('User', '')
            if host_user:
                host_users.append(host_user)
            if alias and hostname:
                hosts.append({'alias': alias, 'hostname': hostname})

    if not user:
        unique_host_users = sorted(set(host_users))
        if len(unique_host_users) == 1:
            user = unique_host_users[0]

    hosts.sort(key=lambda x: x['alias'])
    return {'user': user, 'hosts': hosts}


def sync_ssh_sites(doc: tomlkit.TOMLDocument) -> bool:
    """Reverse-sync ssh config.d sites from live config into local.toml."""
    if not SSH_CONFIG_D.exists():
        return False

    changed = False
    ssh_table = ensure_table(doc, 'variables', 'ssh')

    for site_file in sorted(SSH_CONFIG_D.iterdir()):
        if site_file.name.startswith('.') or not site_file.is_file():
            continue
        parsed = parse_ssh_config_site(site_file, site_file.name)
        if parsed is None:
            continue

        site_table = ensure_table(ssh_table, site_file.name)
        changed |= sync_string(site_table, 'user', parsed['user'])

        live_hosts = parsed['hosts']
        existing_hosts = normalize_ssh_hosts(site_table.get('hosts', []))
        if existing_hosts != live_hosts:
            aot = tomlkit.aot()
            for entry in live_hosts:
                t = tomlkit.table()
                t.add('alias', entry['alias'])
                t.add('hostname', entry['hostname'])
                aot.append(t)
            site_table['hosts'] = aot
            changed = True

    return changed


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

    # glab: runtime state + host container_registry_domains
    glab_changed = sync_glab_config(doc)
    changed |= glab_changed

    # ssh: config.d sites (user + hosts per site)
    ssh_changed = sync_ssh_sites(doc)
    changed |= ssh_changed

    if changed:
        LOCAL_TOML.write_text(tomlkit.dumps(doc))


if __name__ == '__main__':
    main()
