# Dotfiles Repository

Cross-platform dotfiles managed by [dotter](https://github.com/SuperCuber/dotter).

## Dotter Template Syntax

### Built-in Variables

```handlebars
{{dotter.linux}}      # true on Linux
{{dotter.windows}}    # true on Windows
{{dotter.macos}}      # true on macOS
{{dotter.hostname}}   # machine hostname
```

### Built-in Helpers

```handlebars
{{env_var "VAR_NAME"}}                # read environment variable
{{command_output "cmd"}}              # execute command, return stdout
{{command_success "cmd"}}             # true if command exits 0
{{trim "  hello  "}}                  # trim whitespace -> "hello"
{{to_lower_case "HELLO"}}             # lowercase -> "hello"
{{to_upper_case "hello"}}             # uppercase -> "HELLO"
{{replace "old" "o" "0"}}             # string replace -> "0ld"
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
{
  "api_key": "{{replace (command_output 'rbw get my-api-key') '\n' ''}}"
}
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

### Commands

```bash
dotter deploy           # deploy dotfiles
dotter deploy --force   # overwrite existing files
dotter deploy --dry-run # preview changes
```
