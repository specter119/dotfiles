# Templates and variables

Dotter treats any file containing `{{` as a template; `.tmpl` is not required.
Built-in variables, helpers, and expression syntax are upstream:
<https://github.com/SuperCuber/dotter>.

## Template rendering

- Put standalone control blocks on bare lines. Dotter drops a line that holds
  nothing but a block statement, so the render carries no trace of it.
- Never prefix a control block with the format's comment marker: `# {{#if}}`
  renders as a `# ` line, and the target then differs from the render on every
  deploy.
- Use `# ---` for a comment separator that must survive rendering.
- Reduce redundant `#if` guards: an empty list or table renders zero items under
  `#each` without an outer guard. Use `#if` only when the variable may be
  undefined.
- In `#each`, package-level variables need `@root.`
  (`@root.enterprise-artifact.user_id`). A relative path fails to resolve and
  the expression silently renders empty.
- JSON has no comments: standalone controls go on bare lines; inline controls
  (for example `{{#unless @last}},{{/unless}}`) stay inline with the value they
  terminate.
- YAML: quote inline scalar values (`repo: "{{repo}}"`, `- "{{this}}"`).
  Preserve the target tool's unquoted form when reverse sync needs identical
  bytes, as in `glab/config.yml`.

## WSL detection

```handlebars
{{#if (command_success "uname -r | grep -qi wsl")}}
  # WSL-specific config
{{/if}}

{{#if (and dotter.linux (not (command_success "uname -r | grep -qi wsl")))}}
  # Pure Linux (not WSL)
{{/if}}
```

## Secret injection

Inject secrets from Bitwarden with `rbw`:

```handlebars
{ "api_key": "{{replace (command_output "rbw get my-api-key") "\n" ""}}" }
```

`replace ... "\n" ""` removes the trailing newline. Do not put a secret in
`local.toml` or a tracked file.

## Variable schema

### Override order

```toml
# .dotter/global.toml
[package_name.variables.package_name]
scalar_value = ""
nested_value = { key_a = "", key_b = "" }
```

```toml
# .dotter/local.toml
[variables.package_name]
scalar_value = "local"
nested_value = { key_b = "overridden" }
```

Dotter merges variables from selected packages, then recursively overrides them
with top-level `[variables]` from `local.toml` by variable name. Scalar values
with the same name are replaced; tables are merged by key.

### Source rules

- **Per-machine / not synced**: define a placeholder in `global.toml`, override
  it from top-level `[variables]` in `.dotter/local.toml`.
- **Tool-private**: use a namespaced table, e.g. `[magpie.variables.magpie]` and
  `[variables.magpie]`.
- **Namespacing is mandatory**: in `global.toml`, variables live under
  `[pkg.variables.pkg]`. Dotter strict mode requires the template access path
  `pkg.var_name` to match the definition path. Un-namespaced variables fail in
  `#each`; `#if` silently skips, so the variable is not actually registered.
- **Cross-package shared variables**: use the owning tool's namespace. Consuming
  a variable does not transfer ownership.
- **Shareable secrets**: keep inline `rbw get` in templates or scripts; do not
  store them in `local.toml`.
- **Public client credentials**: non-personal, identical on every machine, and
  published upstream may stay hardcoded. `chromium/chromium-flags.conf` carries
  the Chromium project's public OAuth2 client id/secret; these are not personal
  secrets.

Checks and evidence live in
`.agents/skills/dotfiles-config-rendering-review/SKILL.md`.

### Declarations

Declarations and defaults live in `.dotter/global.toml`. Live/local conversions
and reverse-sync coverage live in
`.dotter/scripts/live_config_reverse_sync.py`.

Find template references:

```sh
rg --hidden -n -g '!AGENTS.md' -g '!.git/**' -g '!.jj/**' -F '<namespace.variable>'
```

Keep these user-maintained, not reverse-synced: `agent.magpie_apikey`,
`aria2.rpc_secret`, `container.enterprise_mirrors`, `fcitx5.theme`,
`codex.model_provider`.

Package-local variable contracts may live in the package README when the package
has its own layout. The rclone Dropbox credentials are an example:
[`rclone/README.md#variables`](../rclone/README.md#variables).

`codex.local_mcp_servers` is user-maintained and not reverse-synced. Each entry
needs a `name` plus either `url` or `command` + `args`; it renders one
machine-local `[mcp_servers.<name>]` table. Servers added with `codex mcp add`
belong there, not in the tracked template.

An absent `pi.subagent_model` intentionally inherits the main agent model.
`enterprise-artifact.npm_registry` excludes the URL scheme.
`voxtype-wsl-bridge.hold_key` must name a key the keyboard actually reports.
`fcitx5.theme` must match an installed theme directory, including case.

## Git identities

The default identity is inline in `git/config`. The enterprise identity is one
fixed leaf, `git/enterprise.conf` → `~/.config/git/enterprise.conf`, rendered
from `variables.git.enterprise.name` / `email` and deployed only while that
table is non-empty (`if = 'git.enterprise'`). `git/wsl.conf` and
`git/windows.conf` emit one `includeIf` per entry in `enterprise.dirs_wsl` /
`enterprise.dirs_windows`, because the same directory has a different path form
on each platform. `jj/config.toml` renders `variables.git.repo_identities`
inline and does not use the leaf.

## Root-and-leaf

Use a root dispatcher plus leaf configurations for one config with multiple
independent scopes:

1. Define a namespaced collection in `global.toml`; put per-machine values in
   `local.toml`.
2. Render a root that includes or selects the relevant leaf (Git `includeIf`,
   SSH `Include`).
3. Render each leaf from a tracked template (fixed) or generate an ignored leaf
   in `pre_deploy.sh` (dynamic), then deploy it through the package's directory
   mapping.
4. Reverse-sync only leaves users or tools can modify at runtime.

Do not treat an ignored leaf as disposable unless a pre-deploy generator exists.
Without one it is required source state; deleting it breaks the root dispatcher.
