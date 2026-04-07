# Dotfiles Repository

Cross-platform dotfiles managed by [dotter](https://github.com/SuperCuber/dotter).

## Agent Config Paths (XDG)

**Read this section before modifying any agent configs.**

This repo manages configs for multiple AI coding agents. Their paths follow XDG spec (`~/.config/<name>`) instead of defaults (`~/.<name>`):

| Agent   | Env Var               | Path                |
| ------- | --------------------- | ------------------- |
| Codex   | `CODEX_HOME`          | `~/.config/codex`   |
| Claude  | `CLAUDE_CONFIG_DIR`   | `~/.config/claude`  |
| Pi      | `PI_CODING_AGENT_DIR` | `~/.config/pi`      |
| Copilot | `COPILOT_HOME`        | `~/.config/copilot` |
| Gemini  | `GEMINI_CLI_HOME`     | `~/.config/gemini`  |
| Qoder   | `QODERCLI_HOME`       | `~/.config/qoder`   |

When reading or writing agent configs, use these paths.

## Dotter Templates

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

Dotter 变量在本仓库分成两类：`global.toml` / `local.toml` 覆盖变量，以及模板内联 `rbw get` 的共享 secret。

#### 覆盖顺序

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

- `global.toml` 的 `[package.variables]` 是 package 级占位/schema。
- `local.toml` 不使用 `[package.variables]`；它只使用顶层 `[variables]`。
- Dotter 先合并选中 packages 的变量，再用 `local.toml` 的 `[variables]` 按变量名递归覆盖。
- 同名标量会被替换；同名 table 会递归合并子键。
- 没有合理默认值时，优先在 `global.toml` 放空占位，目的是减少模板分支，不表示推荐默认值。

#### 来源规则

- **per-machine / 不跨机器同步**：放进 `global.toml` 占位，由 `.dotter/local.toml` 顶层 `[variables]` 覆盖。
- **可共享 secret**：继续在模板或脚本里直接 `rbw get`，不进 `local.toml`。
- `.dotter/pre_deploy.sh` 只负责 `rbw sync`，用于 deploy 前同步 vault；它不是变量初始化机制。

#### 当前认可的变量 Schema

| Variable | Shape | Source | Notes |
| --- | --- | --- | --- |
| `slock_api_key` | string | `global + local` | 可空；为空时服务仍可渲染 |
| `slock_proxy` | string | `global + local` | 可空；为空时走直连 |
| `git_repo_identities` | table | `global + local` | key 为 identity 名称，value 含 `repo_dir` / `name` / `email` |
| `skm_local_packages` | array of tables | `global + local` | 每项含 `repo`，可选 `skills` |
| `mihomo_direct_suffixes` | array of strings | `global + local` | 可空；为空时不渲染附加规则 |

#### Git Repo Identities

Add repo-scoped Git identities in `.dotter/local.toml` under `variables.git_repo_identities`:

```toml
[variables.git_repo_identities.company_a]
repo_dir = "~/Documents/company-a.repos/"
name = "your-work-name"
email = "your-work-email@company-a.example"

[variables.git_repo_identities.company_b]
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
3. `dotter deploy --force` - deploy with secrets injected

#### Optional Variables with `#each`

**Always wrap `#each` with `#if` to handle undefined variables gracefully.**

Dotter's `#each` fails when the variable is undefined, breaking template rendering. Wrap it with `#if` to skip the block when the variable is missing:

```handlebars
# {{#if my_items}}
# {{#each my_items}}
- name: "{{name}}"
# {{/each}}
# {{/if}}
```

This pattern ensures templates render correctly even when `my_items` is not defined in `local.toml`.

#### YAML Template Tips

When a YAML file is both a Dotter template and pre-commit formatted with `yamlfmt`, keep these rules:

```yaml
# {{#each skm_local_packages}}
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
- Dotter treats any file containing `{{` as a template; `.tmpl` is not a required or special suffix.
- Dotter hook scripts are also templates. Do not write a literal `{{` inside embedded shell or Python snippets; build it at runtime instead, for example `"{" + "{"`.
- After deploy, generated YAML files may contain empty `#` lines left by commented control blocks. It is safe to delete lines matching `^[[:space:]]*#[[:space:]]*$` in both the rendered target and the Dotter cache copy so future deploys stay in sync.

## Commands

```bash
dotter deploy           # deploy dotfiles
dotter deploy --force   # overwrite existing files
dotter deploy --dry-run # preview changes
```
