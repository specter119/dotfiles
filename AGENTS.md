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

## Dotter Template Syntax

### Built-in Variables

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

### Built-in Helpers

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

### WSL Detection

Use `command_success` to detect WSL:

```handlebars
{{#if (command_success "uname -r | grep -qi wsl")}}
  # WSL-specific config
{{/if}}

{{#if (and dotter.linux (not (command_success "uname -r | grep -qi wsl")))}}
  # Pure Linux (not WSL)
{{/if}}
```

### Secret Injection with rbw

Inject secrets from Bitwarden using `rbw get`:

```handlebars
{ "api_key": "{{replace (command_output "rbw get my-api-key") "\n" ""}}" }
```

The `replace ... '\n' ''` removes trailing newline from rbw output.

**Workflow:**

1. `rbw add my-api-key` - store secret in Bitwarden
2. Use `{{replace (command_output 'rbw get my-api-key') '\n' ''}}` in template
3. `dotter deploy --force` - deploy with secrets injected

### Conditional Logic

```handlebars
{{#if (and cond1 cond2)}}...{{/if}}
{{#if (or cond1 cond2)}}...{{/if}}
{{#if (not cond)}}...{{/if}}
```

### Optional Variables with `#each`

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

### Git Enterprise Identities

Add enterprise Git identities in `.dotter/local.toml` under `variables.git_enterprise`:

```toml
[variables.git_enterprise.company_a]
repo_dir = "~/Documents/company-a.repos/"
name = "your-work-name"
email = "your-work-email@company-a.example"

[variables.git_enterprise.company_b]
repo_dir = "~/Documents/company-b.repos/"
name = "your-other-work-name"
email = "your-other-work-email@company-b.example"
```

Each entry generates `git/generated/<key>.conf`, then Dotter links it to `~/.config/git/generated/<key>.conf`.

### YAML Template Tips

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
