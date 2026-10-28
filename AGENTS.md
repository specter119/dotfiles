# Dotfiles Repository

Cross-platform dotfiles managed by [dotter](https://github.com/SuperCuber/dotter).

## Directory Guidance

- `AGENTS.md`: repo-level architecture, package organization, template conventions, variable strategy
- `.dotter/AGENTS.md`: Dotter internals, `pre_deploy` / `post_deploy` scripts, post-deploy patching, and other implementation exceptions
- `agent/AGENTS.md`: cross-tool agent config contracts (skill/subagent routing, delegation placement). Read before editing agent packages.
- `README.md`: concise, user-facing introduction to the repository and its high-level maintenance patterns

If you touch `.dotter/`, read `.dotter/AGENTS.md` first.
If you touch agent packages (`agent`, `droid`, `pi`, and peers), read `agent/AGENTS.md`.

## README Scope

Use `README.md` for the repository's purpose, user-facing configuration patterns, and links to detailed maintenance guidance.

- Include stable concepts useful to prospective users, such as portability, local overrides, secret handling, and reverse sync.
- Keep implementation contracts in `AGENTS.md` or `.dotter/AGENTS.md`: source paths, variable schemas, renderer behavior, template delimiters, deployment mechanics, and validation commands do not belong in the README.
- Link to the owning guidance instead of duplicating implementation detail.

## Agent Config Paths (XDG)

**Read this section before modifying any agent configs.**
**Do not assume default upstream paths like `~/.codex` or `~/.claude`.**

This repo manages configs for multiple AI coding agents. Their paths follow XDG spec (`~/.config/<name>`) instead of defaults (`~/.<name>`):

| Agent       | Env Var                | Path                    |
| ----------- | ---------------------- | ----------------------- |
| Codex       | `CODEX_HOME`           | `~/.config/codex`       |
| Claude      | `CLAUDE_CONFIG_DIR`    | `~/.config/claude`      |
| Pi          | `PI_CODING_AGENT_DIR`  | `~/.config/pi`          |
| Copilot     | `COPILOT_HOME`         | `~/.config/copilot`     |
| Antigravity | `ANTIGRAVITY_CLI_HOME` | `~/.config/antigravity` |
| Qoder       | `QODERCLI_HOME`        | `~/.config/qoder`       |
| Magpie      | —                      | `~/.config/magpie`      |
| DSH         | `DSH_HOME`             | `~/.config/dsh`         |

When reading or writing agent configs, use these paths.

Skill/subagent routing and delegation placement contracts live in [`agent/AGENTS.md`](./agent/AGENTS.md), not here.

## Package Organization

This repo uses Dotter packages as a layered grouping system rather than a flat list of unrelated folders.

- Base packages hold concrete config payloads for one tool or concern
- Higher-level packages compose those base packages into reusable environments
- Current agent-related grouping is intentionally nested:
  - `agent`: shared entry package for agent-facing configs and common glue
  - `agent-tunnel`: agent-adjacent remote/service integrations
  - `agent-runtime`: local runtime support for agent workflows (including the `magpie` gateway)
- `enterprise-artifact` is the single source of enterprise Artifactory credentials and registry endpoints (npm, PyPI, Docker). It deploys `~/.netrc` and `~/.docker/config.json`; `uv` authenticates against the enterprise PyPI index through `~/.netrc`. General tools such as `npm`, `bun`, `magpie` and `uv` do not depend on it; their templates test `dotter.packages.enterprise-artifact` and render the enterprise part only when the package is selected
- `wm` is a group that composes the compositor (`sway`) with the session services that run next to it (`mako`, `waybar`, `avizo`, `cliphist`, `nm-applet`, `udiskie`) and `fcitx5`; `sway` itself has no `depends`
- `nodejs` is a group of `bun` and `npm`; select `bun` alone on machines that do not need npm
- `wsl-guest` is a group for WSL guests: it carries the required Windows env vars and WSLg environment itself, and composes `wsl-ssh-agent`, `voxtype-wsl-bridge` and `wslg-clipboard` (a `~/.local/bin/wl-paste` shim that serves `image/png` from the Windows clipboard, because WSLg only exposes images as `image/bmp` and droid only requests PNG/JPEG)

When changing package names, dependencies, or file mappings, preserve this layered relationship unless the change is explicitly a package-architecture refactor.

## User Services

Graphical-session services are decoupled from the compositor through systemd targets and drop-ins instead of Dotter package conditions. Do not branch on `dotter.packages.<compositor>` in a unit.

- Services use `PartOf=` and `After=graphical-session.target`. Only a service that needs sway itself (`swayidle`, which calls `swaymsg`) belongs to `sway-session.target`; `sway` pulls it in with `Wants=` in the target.
- A service that starts by default carries no `[Install]`. Its package ships `systemd/user/<target>.d/10-<unit>.conf` containing `[Unit] Wants=<unit>`, so selecting the package enables the service and removing it disables the service. Disable it on one machine with `systemctl --user mask`.
- A service that must stay opt-in keeps `[Install]` and ships no drop-in (currently `udiskie`); enable it per machine with `systemctl --user enable`.
- Sway owns the session target lifecycle: `sway/sway/config.d/50-autostart.conf` imports the compositor environment, starts `sway-session.target`, and `sway/sway/session-stop` stops it when sway exits. The login wrapper (`/etc/greetd/sway-run`, outside this repo) must not start the target itself, otherwise services start before `WAYLAND_DISPLAY` is imported.
- Extensions point from the plugin to the host through the host's drop-in directory: `sway/config.d/` for sway snippets (keybindings live with the package that owns the tool) and `voxtype/output-hook.d/` for executables that voxtype runs around typing, via `voxtype/output-hook pre|post`. The host never names its plugins.
- `voxtype-wsl-bridge` brings the daemon up through `default.target.d/` and its socket through `sockets.target.d/`.

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
- **Tool-private variables**: must use namespaced tables, e.g. `[magpie.variables.magpie]` and `[variables.magpie]`.
- **Variables must be namespaced**: in `global.toml`, variables must be defined under `[pkg.variables.pkg]` (e.g. `[opencode.variables.opencode]`), not flat under `[pkg.variables]`. Dotter strict mode requires that the template access path `pkg.var_name` matches the variable definition path; un-namespaced variables trigger `Failed to access variable in strict mode` when used in `#each` (`#if` silently skips so it does not error, but the variable is not actually registered correctly).
- **Cross-package shared variables**: use the owning tool's namespace, e.g. `git.repo_identities` is defined by `git` / `jj` and consumed by both Git and Jujutsu templates.
- **Shareable secrets**: keep using inline `rbw get` in templates or scripts instead of storing them in `local.toml`.
- **Public client credentials**: non-personal, shared credentials that are identical across all machines and published upstream may stay hardcoded in tracked templates. `chromium/chromium-flags.conf` carries the Chromium open-source project's public OAuth2 client id/secret (used for Google account sign-in); these are not personal secrets and are the same on every machine, so they are exempt from the `rbw get` rule.
- Detailed constraints for `.dotter/pre_deploy.sh` and `.dotter/post_deploy.sh` live in `.dotter/AGENTS.md`.

#### Enterprise Gateway Provider Data

Magpie owns provider-level model configuration (`~/.config/magpie/providers.json`) and the agent-side model lists derived from it. Dotter does not manage `providers.json`: the `magpie` package deploys only `settings.json` and `plugins/`, and nothing reverse-syncs the provider list.

- **Codex** uses the `magpie` provider (`codex.model_provider` defaults to `magpie` in `global.toml`; `model_providers.magpie`, key from `agent.magpie_apikey`). Its `model_catalog_json` is `magpie-models.json`, a runtime artifact that `.dotter/post_deploy.sh` fetches from the magpie gateway on every deploy; do not commit or hand-edit it.
- **Pi** no longer has a `pi/models.json` template. `magpie pi <model>` merges a `magpie` provider into the live `~/.config/pi/models.json`, which magpie owns; `.dotter/post_deploy.sh` re-runs it on every deploy with `pi.default_model` from `local.toml` (only when `pi.default_provider` is `magpie`). It then rewrites the `magpie` provider to `openai-responses` for every model. The `magpie` credential in `pi/auth.json` renders from `agent.magpie_apikey`.
- **OpenCode** has no enterprise provider block.

#### Approved Variable Schema

| Variable                                    | Shape            | Source           | Notes                                                                                                                                                                                                         |
| ------------------------------------------- | ---------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `codex.model`                               | string           | `global + local` | Reverse-synced from `config.toml.model`; omitted when empty                                                                                                                                                   |
| `enterprise_proxy.url`                      | string           | `global + local` | Optional; provided by the `enterprise-proxy` variable-only package, used by raft via `WSS_PROXY` (only when `raft.server_url` is empty) and by yt-dlp when set                                                |
| `raft.server_url`                           | string           | `global + local` | Optional; API base URL of a self-hosted Raft server. When set, `raft-computer.service` exports `RAFT_SERVER_URL` and `NODE_OPTIONS=--use-openssl-ca` and omits `WSS_PROXY`; empty targets the hosted service  |
| `yt-dlp.output_dir`                         | string           | `global + local` | yt-dlp output root; defaults to `~/Videos` and can be overridden per machine                                                                                                                                  |
| `codex.model_provider`                      | string           | `global`         | Codex model provider; defaults to `magpie` in `global.toml`, not reverse-synced                                                                                                                               |
| `codex.projects`                            | array of strings | `global + local` | Reverse-synced from trusted live Codex `[projects]` entries and renders that trust list                                                                                                                       |
| `codex.hook_states`                         | array of tables  | `global + local` | Each item has `key` and `trusted_hash`; reverse-synced from `config.toml` `hooks.state`, renders Codex hook trust state                                                                                       |
| `antigravity.trusted_workspaces`            | array of strings | `global + local` | Optional; reverse-synced from `settings.json.trustedWorkspaces`                                                                                                                                               |
| `git.repo_identities`                       | table            | `global + local` | Keyed by identity name; values contain `repo_dir`, `name`, `email`                                                                                                                                            |
| `skm.local_packages`                        | array of tables  | `global + local` | Each item has `repo`, optional `skills`                                                                                                                                                                       |
| `mihomo.direct_suffixes`                    | array of strings | `global + local` | Optional; extra direct rules are omitted when unset                                                                                                                                                           |
| `mihomo.subscriptions`                      | array of tables  | `global + local` | Proxy subscriptions; each item has `name` and either `url` or `rbw` (Bitwarden item holding the URL). Overriding in `local.toml` replaces the whole list                                                      |
| `agent.magpie_apikey`                       | string           | `global + local` | Magpie gateway key rendered into the Codex `model_providers.magpie` bearer token and the Pi `auth.json` `magpie` credential; user-maintained, not reverse-synced                                              |
| `agent.otel_url`                            | string           | `global + local` | Optional; when set, renders the pi `otel` settings block pointing at this OTLP endpoint                                                                                                                       |
| `magpie.model_wires`                        | table            | `global + local` | Maps a provider glob to a model-name rule (e.g. `"oocl-azure/*"` → `"*-sdlc-gs"`); rendered into the magpie `settings.json` `modelWires` field                                                                |
| `magpie.model_compacts`                     | table            | `global + local` | Maps a provider glob to a context-compaction token threshold (e.g. `"oocl-azure/*"` → `272000`); rendered into the magpie `settings.json` `modelCompacts` field; user-maintained, not reverse-synced          |
| `pi.default_model`                          | string           | `global + local` | Pi default model ID; reverse-synced from `settings.json.defaultModel`                                                                                                                                         |
| `pi.default_provider`                       | string           | `global + local` | Pi default provider name; reverse-synced from `settings.json.defaultProvider`                                                                                                                                 |
| `pi.enterprise_packages`                    | array of strings | `global + local` | Optional; extra packages appended to Pi packages list                                                                                                                                                         |
| `pi.last_changelog_version`                 | string           | `global + local` | Pi read changelog version; reverse-synced from `settings.json.lastChangelogVersion` to avoid deploy overwriting local value                                                                                   |
| `pi.subagent_model`                         | table            | `global + local` | Keyed by subagent name → model id; injected into `pi/agents/<name>.md` frontmatter. An absent entry inherits the main agent `defaultModel`, so leaving a subagent unset is intentional inheritance, not a gap |
| `opencode.default_model`                    | string           | `global + local` | opencode default model, format `provider/model`; reverse-synced from `opencode.jsonc.model`                                                                                                                   |
| `opencode.enterprise_tui_plugins`           | array of strings | `global + local` | Optional; TUI plugin entries are omitted when empty                                                                                                                                                           |
| `droid.trusted_folders`                     | array of tables  | `global + local` | Optional; each item has `dir` (folder path) and `trustedAt` (timestamp); reverse-synced from `settings.json.trustedFolders`                                                                                   |
| `glab.default_host`                         | string           | `global + local` | Optional; glab default GitLab hostname; reverse-synced from `config.yml.host`; omitted when empty                                                                                                             |
| `glab.hosts`                                | array of tables  | `global + local` | Each item has `host`, `token`, `user`, optional `container_registry_domains`; reverse-synced from `config.yml.hosts`                                                                                          |
| `glab.last_update_check_timestamp`          | string           | `global + local` | Reverse-synced from `config.yml.last_update_check_timestamp`; avoids deploy overwriting update check state                                                                                                    |
| `glab.last_seen_version`                    | string           | `global + local` | Reverse-synced from `config.yml.last_seen_version`; avoids deploy overwriting version marker                                                                                                                  |
| `multica.server_url`                        | string           | `global + local` | Multica backend API URL; global default `http://localhost:8080` matches the CLI default, overridden per machine                                                                                               |
| `multica.app_url`                           | string           | `global + local` | Multica web app URL; global default `http://localhost:3000` matches the CLI default, overridden per machine                                                                                                   |
| `scoop.lastupdate`                          | string           | `global + local` | Reverse-synced from `config.json.lastupdate` on Windows; avoids deploy overwriting scoop lastupdate timestamp                                                                                                 |
| `uv.index_url`                              | string           | `global + local` | uv pip index URL used when `enterprise-artifact` is not selected; defaults to USTC mirror, overridable per machine                                                                                            |
| `enterprise-artifact.host`                  | string           | `global + local` | Artifactory host; consumed directly by `.netrc`                                                                                                                                                               |
| `enterprise-artifact.user_id`               | string           | `global + local` | Artifactory user id; consumed directly by `.netrc` and combined inline with access_token by npm/Docker templates                                                                                              |
| `enterprise-artifact.access_token`          | string           | `global + local` | Artifactory access token; consumed directly by Bun/netrc and combined inline with user_id by npm/Docker templates                                                                                             |
| `enterprise-artifact.npm_registry`          | string           | `global + local` | Shared npm/Bun registry URL without scheme; used by `~/.npmrc`, `~/.bunfig.toml` and the magpie plugin `bunfig.toml`                                                                                          |
| `enterprise-artifact.pypi_index`            | string           | `global + local` | Enterprise PyPI index URL; replaces `uv.index_url` in `uv.toml` when the package is selected                                                                                                                  |
| `enterprise-artifact.docker_registry_hosts` | array of strings | `global + local` | Docker registry hosts; each renders an `auths` entry with inline base64 auth                                                                                                                                  |
| `voxtype-wsl-bridge.hold_key`               | string           | `global + local` | AutoHotkey key name held to dictate on Windows (default `RAlt`); must be a key the keyboard actually reports, and is rendered into `voxtype-wsl-bridge/windows/voxtype.ahk`                                   |
| `voxtype-wsl-bridge.port`                   | integer          | `global + local` | Loopback TCP port shared by the WSL `voxtype-wsl-bridge.socket` and the Windows AutoHotkey client; default `47821`                                                                                            |
| `voxtype.device`                            | string           | `global + local` | Optional; ALSA capture device for voxtype; the `device` key is omitted when empty, so voxtype follows the system default                                                                                      |

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
1. Render a root dispatcher that includes or selects the relevant leaf configuration, for example Git `includeIf` or SSH `Include`.
1. Render each leaf configuration from one of two sources:
   - **Fixed instances**: keep a tracked leaf template.
   - **Dynamic instances**: generate ignored leaf artifacts in `pre_deploy.sh` from the variable collection, then deploy them through the package's directory mapping.
1. Reverse-sync only leaves that users or tools can modify at runtime.

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
1. Use `{{replace (command_output 'rbw get my-api-key') '\n' ''}}` in template
1. `dotter deploy` - deploy with secrets injected

#### TOML Template Tips

Put control blocks in `# ` comments to keep the raw template parseable by TOML-aware editors.

**Reduce redundant `#if` guards**: when `global.toml` provides an empty list/table default, use `#each` directly in the template without an outer `#if` wrapper. `#each` produces zero items for an empty collection and does not error. Only use `#if` when the variable may be completely undefined (no global default).

```toml
# global.toml gives projects = [], loop directly
[projects]
# {{#each codex.projects}}

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

Keep these rules for YAML Dotter templates:

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
- Quote inline Handlebars values in YAML scalars, for example `repo: "{{repo}}"` and `- "{{this}}"`, unless the target tool writes that value unquoted and Dotter must reproduce its exact bytes (see `glab/config.yml`).

#### JSON Template Tips

JSON has no comments, so Handlebars control blocks split into two forms:

- **Standalone control blocks** (`{{#each}}`, `{{/each}}`, `{{#if}}`, `{{/if}}`) go on `# `-prefixed lines. After rendering, leftover `# ` blank lines are removed by `post_deploy.sh` cleanup. Use `enterprise-artifact/.docker/config.json` as the reference.
- **Inline control blocks** (e.g. `{{#unless @last}},{{/unless}}` for comma separation) stay bare, because they must emit literal characters and cannot be commented out.

```json
{
  "auths": {
# {{#each enterprise-artifact.docker_registry_hosts}}
    "{{this}}": {
      "auth": "{{replace (command_output (replace (replace "printf '%s:%s' '__USER_ID__' '__ACCESS_TOKEN__' | base64" "__USER_ID__" @root.enterprise-artifact.user_id) "__ACCESS_TOKEN__" @root.enterprise-artifact.access_token)) "\n" ""}}"
    }{{#unless @last}},{{/unless}}
# {{/each}}
  }
}
```

- `post_deploy.sh` identifies templates with `# `-prefixed `#if`/`#each` controls by content and strips residual blank `# ` lines from both the rendered target and the Dotter cache.
- **Use `@root.` for package-level variables inside `{{#each}}`**: `#each` makes each item the current context, so relative paths in helper arguments (e.g. `enterprise-artifact.user_id`) fail to resolve inside the loop and the whole expression **silently renders empty** (deploy does not error). Conditions on package-level variables fail the same way. Write `@root.enterprise-artifact.user_id` instead. Templates with only `#if` and no `#each` (e.g. `npm/.npmrc`) are unaffected because the root context is preserved. The same rule applies to `#each` loops in TOML and YAML templates (e.g. `{{#each skm.local_packages}}` referencing package-level variables).

## Live Config Reverse Sync Pattern

When an agent tool modifies its own config file at runtime (e.g., adding trusted folders, switching models), and the Dotter template renders from the same variable source, deploy will overwrite local changes. Solution: reverse-sync live config changes into `local.toml` before deploy, then let the template read from `local.toml`.

See `.dotter/AGENTS.md` for constraints on deploy scripts (POSIX sh, no literal `{{` in embedded code, runtime artifact conventions).

### Local Schema Differences

When a variable is renamed or removed, update the tracked placeholder, template, and documentation to the new schema, but do not silently migrate, copy, or delete a legacy key in `local.toml`.

If a local schema still contains a legacy key, surface the difference and ask the user whether to keep, migrate, or remove it. Deploy and reverse-sync scripts must never make that choice automatically.

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
1. **Tool-side-effect "non-config"** — the user doesn't treat it as config, but the agent tool writes it casually (e.g., trusted folders, dismissal banners). Losing it isn't fatal, but re-setting it after every deploy is annoying.
1. **Time-sensitive markers** — version numbers, read receipts, changelog versions. They have almost no impact on usage, but deploy rollback is confusing ("I already read this changelog, why is it showing again?").
1. **Temporary workaround** — switching models because a quota is exhausted, planning to switch back later. Reverse sync ensures deploy doesn't overwrite the workaround before you switch back.

**Does NOT need reverse sync — user maintains the value deliberately:**

- **Intentionally maintained config** — API keys, manually selected models, and plugin lists that the user explicitly manages in `local.toml`. The tool never modifies them.
- **Static content** — hardcoded in the template, no variable reference.

### Implementation Steps

1. **Declare the variable** — add an empty placeholder in `global.toml`, register in the Approved Variable Schema in this file
1. **Reference in template** — render with `{{#each}}` / `{{#if}}` in the corresponding template
1. **Add sync function** — write a normalize-compare-write function in `live_config_reverse_sync.py`
1. **Register in main()** — call the sync function in the corresponding agent block

### Variable Types and Sync Functions

| live config format                     | local.toml format         | recommended approach                                                                                           | reference function                |
| -------------------------------------- | ------------------------- | -------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| string                                 | string                    | `sync_string(table, 'key', data.get('field'))`                                                                 | pi `default_model`, codex `model` |
| `dict[path, {trust_level: "trusted"}]` | `string[]`                | `sync_projects` — uses `normalize_projects`                                                                    | codex `projects`                  |
| `dict[str, {trustedAt: str}]`          | `[[aot]]` array of tables | `sync_trusted_folders` — uses `normalize_trusted_folders` (live) + `normalize_existing_trusted_folders` (TOML) | droid `trusted_folders`           |
| `string[]`                             | inline array              | `sync_trusted_workspaces` — uses `normalize_trusted_workspaces` for both sides                                 | antigravity `trusted_workspaces`  |

## Commands

```bash
dotter deploy           # deploy dotfiles
dotter deploy --force   # overwrite existing files
dotter deploy --dry-run # preview changes
```
