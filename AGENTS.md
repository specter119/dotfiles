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

When a package should remain in the default package groups but must not overwrite the real live config on a specific machine, remap its deploy target to a blackhole directory such as `~/.cache/dotter-blackhole/<package>` in a machine-specific include like `.dotter/wsl.toml`.

- Use this when the package is still part of shared package composition, but the actual live path is intentionally managed locally and should not be overwritten by Dotter.
- Prefer this over removing the package from global groups when you still want dependency structure, variables, and repo defaults to stay intact.
- Keep the blackhole target obviously non-live and disposable, typically under `~/.cache/dotter-blackhole/`.
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
- **服务 / 工具私有变量**：使用 namespaced table，例如 `[slock.variables.slock]` 和 `[variables.slock]`，不要继续使用 `slock_api_key` 这类扁平变量名。
- **跨 package 共享变量**：使用拥有者工具的 namespace，例如 `git.repo_identities` 由 `git` / `jj` 定义，并同时被 Git 和 Jujutsu 模板消费。
- **Shareable secrets**: keep using inline `rbw get` in templates or scripts instead of storing them in `local.toml`.
- Detailed constraints for `.dotter/pre_deploy.sh` and `.dotter/post_deploy.sh` live in `.dotter/AGENTS.md`.

#### Approved Variable Schema

| Variable | Shape | Source | Notes |
| --- | --- | --- | --- |
| `codex.model_provider` | string | `global + local` | 可为空；为空时不渲染顶层 `model_provider` |
| `slock.api_key` | string | `global + local` | 可为空；服务仍应正常渲染 |
| `slock.wss_proxy` | string | `global + local` | 可为空；未设置时不渲染 proxy env |
| `codex.trusted_projects` | array of strings | `global + local` | 可为空；用于渲染 Codex `[projects]` trust 列表 |
| `codex.hook_states` | array of tables | `global + local` | 每项包含 `key` 和 `trusted_hash`；用于渲染 Codex hook trust state |
| `antigravity.trusted_workspaces` | array of strings | `global + local` | 可为空；用于渲染 Antigravity `trustedWorkspaces` |
| `git.repo_identities` | table | `global + local` | 以 identity 名称为 key；值包含 `repo_dir`、`name`、`email` |
| `skm.local_packages` | array of tables | `global + local` | 每项包含 `repo`，可选 `skills` |
| `mihomo.direct_suffixes` | array of strings | `global + local` | 可为空；未设置时不渲染额外直连规则 |
| `agent.enterprise_cn_base_url` | string | `global + local` | 共享 base URL；为空时不渲染 provider |
| `agent.enterprise_cn_providers` | table of tables | `global + local` | 以 provider 名为 key；值含 `api_key`；用 `#each` 渲染多 provider |
| `pi.default_model` | string | `global + local` | Pi 默认模型 ID；由 sync 脚本从部署侧同步 |
| `pi.default_provider` | string | `global + local` | Pi 默认 provider 名；由 sync 脚本从部署侧同步 |
| `pi.enterprise_packages` | array of strings | `global + local` | 可为空；追加到 Pi packages 列表的额外包 |
| `pi.last_changelog_version` | string | `global + local` | Pi 已读 changelog 版本；由 sync 脚本从部署侧同步，避免部署覆盖本地值 |
| `opencode.default_model` | string | `global + local` | opencode 默认模型，格式 `provider/model`；由 sync 脚本同步 |
| `opencode.enterprise_tui_plugins` | array of strings | `global + local` | 可为空；为空时不渲染 TUI plugin 条目 |

| `droid.default_model` | string | `global + local` | Factory Droid 默认模型；由 sync 脚本同步 |

#### Git Repo Identities

Repo-scoped Git identities 写在 `.dotter/local.toml` 的 `variables.git.repo_identities` 下：

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

Each entry generates `git/generated/<key>.conf`, then Dotter links it to `~/.config/git/generated/<key>.conf`.

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

**Always wrap `#each` with `#if`** — Dotter's `#each` fails when the variable is undefined. This rule applies to both TOML and YAML templates.

Put control blocks in `# ` comments to keep the raw template parseable by TOML-aware editors. **Combine `#if`+`#each` (and `/each`+`/if`) onto a single `# ` line** to minimize residual empty-comment lines after rendering:

```toml
[projects]
# {{#if codex.trusted_projects}}{{#each codex.trusted_projects}}

[projects."{{this}}"]
trust_level = "trusted"
# {{/each}}{{/if}}
```

- Each combined control line produces exactly **one** `# ` residue line after rendering (instead of two).
- `post_deploy.sh` removes these residual `# ` lines from both the deployed target and the Dotter cache so they stay in sync and don't trigger false diffs on subsequent deploys.
- Dotter treats any file containing `{{` as a template; `.tmpl` is not a required or special suffix.

#### YAML Template Tips

When a YAML file is both a Dotter template and pre-commit formatted with `yamlfmt`, keep these rules:

```yaml
# {{#if skm.local_packages}}
# {{#each skm.local_packages}}
- repo: "{{repo}}"
  # {{#if skills}}
  skills:
    # {{#each skills}}
    - "{{this}}"
    # {{/each}}
# {{/if}}
# {{/each}}
# {{/if}}
```

- Put control blocks like `#each` and `#if` in YAML comments so YAML formatters and editors can still parse the file.
- Quote inline Handlebars values in YAML scalars, for example `repo: "{{repo}}"` and `- "{{this}}"`. Unquoted forms may be rewritten into invalid `{ { repo } }` style text by formatters.
- After deploy, generated files may contain empty `#` lines left by commented control blocks. `post_deploy.sh` removes lines matching `^[[:space:]]*#[[:space:]]*$` from both the rendered target and the Dotter cache copy so future deploys stay in sync.

## Commands

```bash
dotter deploy           # deploy dotfiles
dotter deploy --force   # overwrite existing files
dotter deploy --dry-run # preview changes
```
