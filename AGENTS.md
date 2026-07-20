# Dotfiles Repository

Cross-platform dotfiles managed by [dotter](https://github.com/SuperCuber/dotter).

## Directory Guidance

- `AGENTS.md`: repo-level architecture, package organization, template conventions, variable strategy
- `.dotter/AGENTS.md`: Dotter internals, `pre_deploy` / `post_deploy` scripts, post-deploy patching, and other implementation exceptions

If you touch `.dotter/`, read `.dotter/AGENTS.md` first.

## Agent Config Paths (XDG)

**Read this section before modifying any agent configs.**
**Do not assume default upstream paths like `~/.codex` or `~/.claude`.**

This repo manages configs for multiple AI coding agents. Their paths follow XDG spec (`~/.config/<name>`) instead of defaults (`~/.<name>`):

| Agent   | Env Var               | Path                |
| ------- | --------------------- | ------------------- |
| Codex   | `CODEX_HOME`          | `~/.config/codex`   |
| Claude  | `CLAUDE_CONFIG_DIR`   | `~/.config/claude`  |
| Pi      | `PI_CODING_AGENT_DIR` | `~/.config/pi`      |
| Copilot | `COPILOT_HOME`        | `~/.config/copilot` |
| Antigravity | `ANTIGRAVITY_CLI_HOME` | `~/.config/antigravity` |
| Qoder   | `QODERCLI_HOME`       | `~/.config/qoder`   |

When reading or writing agent configs, use these paths.

## Package Organization

This repo uses Dotter packages as a layered grouping system rather than a flat list of unrelated folders.

- Base packages hold concrete config payloads for one tool or concern
- Higher-level packages compose those base packages into reusable environments
- Current agent-related grouping is intentionally nested:
  - `agent`: shared entry package for agent-facing configs and common glue
  - `agent-tunnel`: agent-adjacent remote/service integrations
  - `agent-runtime`: local runtime support for agent workflows

When changing package names, dependencies, or file mappings, preserve this layered relationship unless the change is explicitly a package-architecture refactor.

## Dotter Templates

### Blackhole Mapping

When a package should remain in the default package groups but must not overwrite the real live config on a specific machine, remap its deploy target to a blackhole directory such as `$XDG_RUNTIME_DIR/dotter/blackhole-<package>` in a machine-specific include like `.dotter/wsl.toml`.

- Use this when the package is still part of shared package composition, but the actual live path is intentionally managed locally and should not be overwritten by Dotter.
- Prefer this over removing the package from global groups when you still want dependency structure, variables, and repo defaults to stay intact.
- Keep the blackhole target obviously non-live and disposable, in `$XDG_RUNTIME_DIR/dotter/blackhole-<package>`.
- Document the real live config ownership nearby so future changes do not accidentally assume Dotter still controls the production path.

### Template Basics

#### Built-in Variables

```handlebars
{{dotter.linux}}
# true on Linux
{{dotter.windows}}
# true on Windows
{{dotter.macos}}
# true on macOS
{{dotter.hostname}}
# machine hostname
```

#### Built-in Helpers

```handlebars
{{env_var "VAR_NAME"}}
# read environment variable
{{command_output "cmd"}}
# execute command, return stdout
{{command_success "cmd"}}
# true if command exits 0
{{trim "  hello  "}}
# trim whitespace -> "hello"
{{to_lower_case "HELLO"}}
# lowercase -> "hello"
{{to_upper_case "hello"}}
# uppercase -> "HELLO"
{{replace "old" "o" "0"}}
# string replace -> "0ld"
```

#### WSL Detection

Use `command_success` to detect WSL:

```handlebars
{{#if (command_success "uname -r | grep -qi wsl")}}
  # WSL-specific config
{{/if}}

{{#if (and dotter.linux (not (command_success "uname -r | grep -qi wsl")))}}
  # Pure Linux (not WSL)
{{/if}}
```

#### Conditional Logic

```handlebars
{{#if (and cond1 cond2)}}...{{/if}}
{{#if (or cond1 cond2)}}...{{/if}}
{{#if (not cond)}}...{{/if}}
```

### Variable Contract

Dotter variables in this repo fall into two categories: `global.toml` / `local.toml` override variables, and shared secrets injected inline with `rbw get` inside templates.

#### Override Order

```toml
# .dotter/global.toml
[package_name.variables]
scalar_value = ""
nested_value = { key_a = "", key_b = "" }
```

```toml
# .dotter/local.toml
[variables]
scalar_value = "local"
nested_value = { key_b = "overridden" }
```

- `[package.variables]` in `global.toml` defines package-level placeholders and schema.
- `local.toml` does not use `[package.variables]`; it only uses top-level `[variables]`.
- Dotter first merges variables from the selected packages, then recursively overrides them with top-level `[variables]` from `local.toml` by variable name.
- Scalar values with the same name are replaced; tables with the same name are recursively merged by key.
- If there is no sensible default, prefer an empty placeholder in `global.toml` to reduce template branching. This is a schema choice, not a recommended default value.

#### Source Rules

- **Per-machine / not synced across machines**: define a placeholder in `global.toml`, then override it from top-level `[variables]` in `.dotter/local.toml`.
- **Tool-private variables**: must use namespaced tables, e.g. `[raft.variables.raft]` and `[variables.raft]`. Never use flat variable names like `raft_api_key`.
- **Variables must be namespaced**: in `global.toml`, variables must be defined under `[pkg.variables.pkg]` (e.g. `[opencode.variables.opencode]`), not flat under `[pkg.variables]`. Dotter strict mode requires that the template access path `pkg.var_name` matches the variable definition path; un-namespaced variables trigger `Failed to access variable in strict mode` when used in `#each` (`#if` silently skips so it does not error, but the variable is not actually registered correctly).
- **Cross-package shared variables**: use the owning tool's namespace, e.g. `git.repo_identities` is defined by `git` / `jj` and consumed by both Git and Jujutsu templates.
- **Shareable secrets**: keep using inline `rbw get` in templates or scripts instead of storing them in `local.toml`.
- Detailed constraints for `.dotter/pre_deploy.sh` and `.dotter/post_deploy.sh` live in `.dotter/AGENTS.md`.

#### Approved Variable Schema

| Variable | Shape | Source | Notes |
| --- | --- | --- | --- |
| `codex.model_provider` | string | `global + local` | Optional; when empty, top-level `model_provider` is omitted |
| `raft.api_key` | string | `global + local` | Optional; service renders normally even when empty |
| `enterprise_proxy.url` | string | `global + local` | Optional; provided by the `enterprise-proxy` variable-only package, used by raft via `WSS_PROXY` and by yt-dlp when set |
| `yt-dlp.output_dir` | string | `global + local` | yt-dlp output root; defaults to `~/Videos` and can be overridden per machine |
| `codex.trusted_projects` | array of strings | `global + local` | Optional; renders Codex `[projects]` trust list |
| `codex.hook_states` | array of tables | `global + local` | Each item has `key` and `trusted_hash`; renders Codex hook trust state |
| `antigravity.trusted_workspaces` | array of strings | `global + local` | Optional; renders Antigravity `trustedWorkspaces` |
| `git.repo_identities` | table | `global + local` | Keyed by identity name; values contain `repo_dir`, `name`, `email` |
| `skm.local_packages` | array of tables | `global + local` | Each item has `repo`, optional `skills` |
| `mihomo.direct_suffixes` | array of strings | `global + local` | Optional; extra direct rules are omitted when unset |
| `agent.enterprise_clients` | table of tables | `global + local` | Enterprise gateway client identities; each entry keyed by client name contains `api_key`; used in nested `#each` with deployments |
| `agent.enterprise_deployments` | table of tables | `global + local` | Enterprise gateway deployment paths; each entry keyed by deployment name contains `base_url`, `models_file`, optional `npm`; used in nested `#each` with clients |
| `pi.default_model` | string | `global + local` | Pi default model ID; synced from deploy side by sync script |
| `pi.default_provider` | string | `global + local` | Pi default provider name; synced from deploy side by sync script |
| `pi.enterprise_packages` | array of strings | `global + local` | Optional; extra packages appended to Pi packages list |
| `pi.last_changelog_version` | string | `global + local` | Pi read changelog version; synced by sync script to avoid deploy overwriting local value |
| `opencode.default_model` | string | `global + local` | opencode default model, format `provider/model`; synced by sync script |
| `opencode.enterprise_tui_plugins` | array of strings | `global + local` | Optional; TUI plugin entries are omitted when empty |
| `droid.trusted_folders` | array of tables | `global + local` | Optional; each item has `dir` (folder path) and `trustedAt` (timestamp); renders Droid `trustedFolders` |
| `glab.default_host` | string | `global + local` | Optional; glab default GitLab hostname; omitted when empty |
| `glab.hosts` | array of tables | `global + local` | Each item has `host`, `token`, `user`, optional `container_registry_domains`; renders glab host config |
| `glab.last_update_check_timestamp` | string | `global + local` | Reverse-synced from live config; avoids deploy overwriting update check state |
| `glab.last_seen_version` | string | `global + local` | Reverse-synced from live config; avoids deploy overwriting version marker |
| `ssh.{site}.user` | string | `global + local` | Per-site SSH wildcard user (e.g. `ssh.hkg.user`); omitted when empty |
| `ssh.{site}.hosts` | array of tables | `global + local` | Each item has `alias` and `hostname`; renders specific Host entries under site prefix |
| `scoop.lastupdate` | string | `global + local` | Reverse-synced from live config on Windows; avoids deploy overwriting scoop lastupdate timestamp |

#### Git Repo Identities

Repo-scoped Git identities are defined in `.dotter/local.toml` under `variables.git.repo_identities`:

```toml
[variables.git.repo_identities.company_a]
repo_dir = "~/Documents/company-a.repos/"
name = "your-work-name"
email = "your-work-email@company-a.example"

[variables.git.repo_identities.company_b]
repo_dir = "~/Documents/company-b.repos/"
name = "your-other-work-name"
email = "your-other-work-email@company-b.example"
```

Each entry renders a matching Git conditional include and Jujutsu repository scope. The matching Git leaf config is deployed from `git/generated/<key>.conf` to `~/.config/git/generated/<key>.conf`.

#### Root-and-Leaf Subconfiguration Pattern

Use a root-and-leaf layout for a single configuration with multiple independent scopes:

1. Define a namespaced collection in `global.toml` and its per-machine values in `local.toml`.
2. Render a root dispatcher that includes or selects the relevant leaf configuration, for example Git `includeIf` or SSH `Include`.
3. Render each leaf configuration from one of two sources:
   - **Fixed instances**: keep a tracked leaf template, such as `ssh/config.d/<site>`.
   - **Dynamic instances**: generate ignored leaf artifacts in `pre_deploy.sh` from the variable collection, then deploy them through the package's directory mapping.
4. Reverse-sync only leaves that users or tools can modify at runtime.

Do not treat an ignored leaf as disposable unless a pre-deploy generator exists. Without one, it is still required source state and deleting it breaks the root dispatcher's selected configuration.

### Template Patterns

#### Secret Injection with rbw

Inject secrets from Bitwarden using `rbw get`:

```handlebars
{ "api_key": "{{replace (command_output "rbw get my-api-key") "\n" ""}}" }
```

The `replace ... '\n' ''` removes trailing newline from rbw output.

**Workflow:**

1. `rbw add my-api-key` - store secret in Bitwarden
2. Use `{{replace (command_output 'rbw get my-api-key') '\n' ''}}` in template
3. `dotter deploy` - deploy with secrets injected

#### TOML Template Tips

Put control blocks in `# ` comments to keep the raw template parseable by TOML-aware editors.

**Reduce redundant `#if` guards**: when `global.toml` provides an empty list/table default, use `#each` directly in the template without an outer `#if` wrapper. `#each` produces zero items for an empty collection and does not error. Only use `#if` when the variable may be completely undefined (no global default).

```toml
# global.toml gives trusted_projects = [], loop directly
[projects]
# {{#each codex.trusted_projects}}

[projects."{{this}}"]
trust_level = "trusted"
# {{/each}}

# combine control lines to reduce residual comment lines
# {{#if some_undefined_var}}{{#each some_undefined_var}}...
# {{/each}}{{/if}}
```

- Combining `#if`+`#each` (and `/each`+`/if`) onto a single `# ` line reduces residual empty comment lines after rendering.
- `post_deploy.sh` identifies templates containing comment-wrapped `#if` or `#each` controls by content, then removes residual `# ` lines from both the rendered target and the Dotter cache regardless of filename extension. Use `# ---` for a comment separator that must remain.
- Dotter treats any file containing `{{` as a template; `.tmpl` is not a required or special suffix.

#### YAML Template Tips

When a YAML file is both a Dotter template and pre-commit formatted with `yamlfmt`, keep these rules:

```yaml
# local_packages has global default [], loop directly; skills is per-item optional, keep #if
# {{#each skm.local_packages}}
- repo: "{{repo}}"
  # {{#if skills}}
  skills:
    # {{#each skills}}
    - "{{this}}"
    # {{/each}}
  # {{/if}}
# {{/each}}
```

- Put control blocks like `#each` and `#if` in YAML comments so YAML formatters and editors can still parse the file.
- Quote inline Handlebars values in YAML scalars, for example `repo: "{{repo}}"` and `- "{{this}}"`. Unquoted forms may be rewritten into invalid `{ { repo } }` style text by formatters.

## Live Config Reverse Sync Pattern

When an agent tool modifies its own config file at runtime (e.g., adding trusted folders, switching models), and the Dotter template renders from the same variable source, deploy will overwrite local changes. Solution: reverse-sync live config changes into `local.toml` before deploy, then let the template read from `local.toml`.

See `.dotter/AGENTS.md` for constraints on deploy scripts (POSIX sh, no literal `{{` in embedded code, runtime artifact conventions).

### Droid Settings Boundary

`droid/config/settings.json` is source-managed static configuration except for `trustedFolders`.
`droid.trusted_folders` is a local variable reverse-synced from the live file because Droid
writes trust records as a machine-specific side effect. All other Droid settings have
meaningful behavior and are intentionally not Dotter variables or reverse-synced.

When any other Droid setting differs between the repository and `~/.factory/settings.json`,
resolve that drift manually by choosing the intended source or live value. Do not turn a
field into a template variable merely because it differs.

### Flow

```
live config changes (tool modifies at runtime)
      ↓
pre_deploy.sh → live_config_reverse_sync.py
      ↓
local.toml variables updated
      ↓
Dotter template rendering (reads from local.toml)
      ↓
deployed config preserves changes
```

### Decision Framework: When to Add a Local Variable + Reverse Sync

Two sequential decisions: **should it be a local variable**, then **should it be reverse-synced**.

#### Step 1: Does it need a local variable?

Make a value a Dotter variable in `local.toml` (rather than hardcoding in the template or `global.toml`) when:

- **Differs across machines** — the same template must produce different results on different machines (e.g., enterprise model at work, public model at home)
- **Should not be in the repo** — secrets, credentials, personal tokens must not be committed
- **Tool modifies at runtime** — the agent tool will change this value locally; the template must reflect the live value, not a repo default

If the value is the same on all machines and never changes, hardcode it in the template — no local variable needed.

#### Step 2: Does it need reverse sync?

Once a value is a local variable, decide whether it should be reverse-synced from the live config back to `local.toml`:

**Needs reverse sync — tool modifies the value, deploy would lose it:**

1. **Machine-specific config** — same setting differs across machines (e.g., default model). The user may switch it via the tool UI on machine A; deploy must preserve that choice, not overwrite with another machine's or the repo's default.
2. **Tool-side-effect "non-config"** — the user doesn't treat it as config, but the agent tool writes it casually (e.g., trusted folders, dismissal banners). Losing it isn't fatal, but re-setting it after every deploy is annoying.
3. **Time-sensitive markers** — version numbers, read receipts, changelog versions. They have almost no impact on usage, but deploy rollback is confusing ("I already read this changelog, why is it showing again?").
4. **Temporary workaround** — switching models because a quota is exhausted, planning to switch back later. Reverse sync ensures deploy doesn't overwrite the workaround before you switch back.

**Does NOT need reverse sync — user maintains the value deliberately:**
- **Intentionally maintained config** — API keys, trusted project lists, plugin lists that the user explicitly manages in `local.toml`. The tool never modifies them.
- **Static content** — hardcoded in the template, no variable reference.

### Implementation Steps

1. **Declare the variable** — add an empty placeholder in `global.toml`, register in the Approved Variable Schema in this file
2. **Reference in template** — render with `{{#each}}` / `{{#if}}` in the corresponding template
3. **Add sync function** — write a normalize-compare-write function in `live_config_reverse_sync.py`
4. **Register in main()** — call the sync function in the corresponding agent block

### Variable Types and Sync Functions

| live config format | local.toml format | recommended approach | reference function |
|---|---|---|---|
| string | string | `sync_string(table, 'key', data.get('field'))` | pi `default_model` |
| string (conditional) | string | `sync_string(table, 'key', val, fallback='', remove_if_empty=True)` | codex `model_provider` |
| `dict[str, {trustedAt: str}]` | `[[aot]]` array of tables | `sync_trusted_folders` — uses `normalize_trusted_folders` (live) + `normalize_existing_trusted_folders` (TOML) | droid `trusted_folders` |
| `string[]` | inline array | `sync_trusted_workspaces` — uses `normalize_trusted_workspaces` for both sides | antigravity `trusted_workspaces` |

### Current Coverage

| Agent | Variable | Format | Source |
|---|---|---|---|
| pi | `default_model` | string | `settings.json.defaultModel` |
| pi | `default_provider` | string | `settings.json.defaultProvider` |
| pi | `last_changelog_version` | string | `settings.json.lastChangelogVersion` |
| droid | `trusted_folders` | `[[aot]]` | `settings.json.trustedFolders` |
| opencode | `default_model` | string | `opencode.jsonc.model` |
| codex | `default_model` | string | `config.toml.model` |
| codex | `model_provider` | string (conditional) | `config.toml.model_provider` |
| antigravity | `trusted_workspaces` | `string[]` | `settings.json.trustedWorkspaces` |
| glab | `default_host` | string | `config.yml.host` |
| glab | `hosts` | `[[aot]]` | `config.yml.hosts` |
| glab | `last_update_check_timestamp` | string | `config.yml.last_update_check_timestamp` |
| glab | `last_seen_version` | string | `config.yml.last_seen_version` |
| ssh | `{site}.user` | string | `config.d/{site}` wildcard `User` |
| ssh | `{site}.hosts` | `[[aot]]` | `config.d/{site}` specific `Host`/`HostName` pairs |
| scoop | `lastupdate` | string | `config.json.lastupdate` (Windows only) |

## Commands"}]

```bash
dotter deploy           # deploy dotfiles
dotter deploy --force   # overwrite existing files
dotter deploy --dry-run # preview changes
```
