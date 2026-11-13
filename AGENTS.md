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

Agent configs are deployed under the XDG spec (`~/.config/<name>`), not the upstream defaults (`~/.<name>`). Resolve deployed paths from `.dotter/global.toml` (`[*.files]`) and the environment overrides from `agent/config/environment.d/agentic-xdg.conf`; machine-specific includes such as `.dotter/wsl.toml` may remap a path.

Skill/subagent routing and delegation placement contracts live in [`agent/AGENTS.md`](./agent/AGENTS.md), not here.

## Package Organization

This repo uses Dotter packages as a layered grouping system rather than a flat list of unrelated folders.

- Base packages hold concrete config payloads for one tool or concern
- Higher-level packages compose those base packages into reusable environments
- Agent-related grouping is intentionally nested: `agent` is the shared entry package for agent-facing configs and common glue, `agent-tunnel` holds agent-adjacent remote/service integrations, and `agent-runtime` holds local runtime support for agent workflows

`enterprise-artifact` is the single source of enterprise Artifactory credentials and registry endpoints. A deployment without it must stay valid, so consumers test `dotter.packages.enterprise-artifact` instead of depending on it. Current package composition and file mappings are defined in `.dotter/global.toml`. Workaround rationale lives next to the workaround (`wsl-guest/`, `droid/bin/wl-paste`, `x11-lowdpi/bin/x11-lowdpi`); do not replace the Scoop wrappers with `fish_user_paths`, which would put the Windows directory ahead of Linux commands.

`depends` expresses a deployment relationship between packages, never a reference between variables. Use it for only two reasons:

- **Grouping**: a package that layers base packages so one selection deploys a whole environment with fewer decisions.
- **Functional coupling**: the dependent software cannot work without the dependency's deployed payload.

Reading another package's variable, or testing `dotter.packages.<name>`, is not a dependency. A template that guards such a value with `#if` has two valid renderings (set and unset) and deploys either way, so it must not declare `depends`. Add `depends` for a variable only when the deployment itself stops making sense without it, that is, the dependent has no working form once the variable is removed.

When changing package names, dependencies, or file mappings, preserve this layered relationship unless the change is explicitly a package-architecture refactor.

## User Services

Graphical-session services are decoupled from the compositor through systemd targets and drop-ins instead of Dotter package conditions. Do not branch on `dotter.packages.<compositor>` in a unit.

- Services use `PartOf=` and `After=graphical-session.target`. Only a service that needs sway itself (`swayidle`, which calls `swaymsg`) belongs to `sway-session.target`; `sway` pulls it in with `Wants=` in the target.
- A service that starts by default carries no `[Install]`. Its package ships `systemd/user/<target>.d/10-<unit>.conf` containing `[Unit] Wants=<unit>`, so selecting the package enables the service and removing it disables the service. Disable it on one machine with `systemctl --user mask`.
- A service that must stay opt-in keeps `[Install]` and ships no drop-in; enable it per machine with `systemctl --user enable`.
- Sway owns the session target lifecycle: `sway/sway/config.d/50-autostart.conf` imports the compositor environment, starts `sway-session.target`, and `sway/sway/session-stop` stops it when sway exits. The login wrapper (`/etc/greetd/sway-run`, outside this repo) must not start the target itself, otherwise services start before `WAYLAND_DISPLAY` is imported.
- Extensions point from the plugin to the host through the host's drop-in directory: `sway/config.d/` for sway snippets (keybindings live with the package that owns the tool) and `voxtype/output-hook.d/` for executables that voxtype runs around typing, via `voxtype/output-hook pre|post`. The host never names its plugins.
- A socket-activated service brings its daemon up through `default.target.d/` and its socket through `sockets.target.d/`.

## Dotter Templates

### Blackhole Mapping

When a package should remain in the default package groups but must not overwrite the real live config on a specific machine, remap its deploy target to a blackhole directory such as `$XDG_RUNTIME_DIR/dotter/blackhole-<package>` in a machine-specific include like `.dotter/wsl.toml`.

- Use this when the package is still part of shared package composition, but the actual live path is intentionally managed locally and should not be overwritten by Dotter.
- Prefer this over removing the package from global groups when you still want dependency structure, variables, and repo defaults to stay intact.
- Keep the blackhole target obviously non-live and disposable, in `$XDG_RUNTIME_DIR/dotter/blackhole-<package>`.
- Document the real live config ownership nearby so future changes do not accidentally assume Dotter still controls the production path.

### Conditional Configuration

Configuration that must exist only when a package is selected or a variable is set stays out of the unconditional path. Prefer **conditional deploy** over **conditional context**, in this order:

1. **Conditional deploy** (preferred): move the conditional part into its own source directory and gate its mapping in the owning package, for example `'wsl-guest-enterprise' = { target = '~/.config', if = 'dotter.packages.enterprise-artifact' }` (same form as `droid/bin`). Name the directory `<package>-<condition>`; it is a source directory, not a Dotter package. Use it whenever the target tool reads a drop-in or include location (`environment.d/`, `<unit>.d/`, `config.d/`, `*.d/`), so the base file carries no condition. Directory mappings into the same target directory coexist, because Dotter links per file.
1. **Conditional context** (fallback): an `#if` inside the template. Use it only when the target is one file with no drop-in or include mechanism (for example `uv.toml`), or when the conditional value is interleaved with unconditional keys of the same structure.

- Confirm in the tool's documentation that it reads the drop-in location before choosing conditional deploy. If you cannot confirm it, use conditional context and record why.
- Test selection with `dotter.packages.<name>` and variables with `#if`, never with `depends` (see Package Organization).
- **CA and TLS settings are enterprise-only.** Anything that trusts a non-default CA or relaxes verification (`NODE_USE_SYSTEM_CA`, `NODE_EXTRA_CA_CERTS`, `--use-openssl-ca`, `system-certs`, `ssl_verify`, and the like) must be gated by `dotter.packages.enterprise-artifact`, or by the variable that makes the setting meaningful (`enterprise_proxy.url`, `raft.server_url`). A machine outside the enterprise group must deploy none of them unless such a variable is set.

### Template Basics

Built-in variables, helpers and expression syntax: [upstream Dotter documentation](https://github.com/SuperCuber/dotter).

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

### Variable Contract

Dotter variables in this repo fall into two categories: `global.toml` / `local.toml` override variables, and shared secrets injected inline with `rbw get` inside templates.

#### Override Order

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

- `[package.variables.package]` in `global.toml` defines namespaced placeholders and schema.
- `local.toml` does not use `[package.variables]`; it only uses top-level `[variables]`.
- Dotter first merges variables from the selected packages, then recursively overrides them with top-level `[variables]` from `local.toml` by variable name.
- Scalar values with the same name are replaced; tables with the same name are recursively merged by key.
- If there is no sensible default, prefer an empty placeholder in `global.toml` to reduce template branching. This is a schema choice, not a recommended default value.

#### Source Rules

- **Per-machine / not synced across machines**: define a placeholder in `global.toml`, then override it from top-level `[variables]` in `.dotter/local.toml`.
- **Tool-private variables**: must use namespaced tables, e.g. `[magpie.variables.magpie]` and `[variables.magpie]`.
- **Variables must be namespaced**: in `global.toml`, variables must be defined under `[pkg.variables.pkg]` (e.g. `[opencode.variables.opencode]`), not flat under `[pkg.variables]`. Dotter strict mode requires that the template access path `pkg.var_name` matches the variable definition path; un-namespaced variables trigger `Failed to access variable in strict mode` when used in `#each` (`#if` silently skips so it does not error, but the variable is not actually registered correctly).
- **Cross-package shared variables**: use the owning tool's namespace; consuming a variable does not transfer ownership.
- **Shareable secrets**: keep using inline `rbw get` in templates or scripts instead of storing them in `local.toml`.
- **Public client credentials**: non-personal, shared credentials that are identical across all machines and published upstream may stay hardcoded in tracked templates. `chromium/chromium-flags.conf` carries the Chromium open-source project's public OAuth2 client id/secret (used for Google account sign-in); these are not personal secrets and are the same on every machine, so they are exempt from the `rbw get` rule.
- Detailed constraints for `.dotter/pre_deploy.sh` and `.dotter/post_deploy.sh` live in `.dotter/AGENTS.md`.

#### Enterprise Gateway Provider Data

Magpie owns `~/.config/magpie/providers.json` and the agent-side model data derived from it; do not turn them into Dotter templates or reverse-sync the provider list. Artifact ownership and refresh hazards are documented in [`.dotter/AGENTS.md`, Runtime Artifacts](.dotter/AGENTS.md#runtime-artifacts).

#### Variable Declarations

Variable declarations and defaults: `.dotter/global.toml`. Live/local conversions and reverse-sync coverage: `.dotter/scripts/live_config_reverse_sync.py`. Find template references with `rg --hidden -n -g '!AGENTS.md' -g '!.git/**' -g '!.jj/**' -F '<namespace.variable>'`.

Keep `agent.magpie_apikey`, `aria2.rpc_secret`, `container.enterprise_mirrors` and `fcitx5.theme` user-maintained, not reverse-synced. `codex.model_provider` is also not reverse-synced.
`codex.local_mcp_servers` is user-maintained and not reverse-synced: each entry needs a `name` plus either `url` or `command` + `args`, and renders one machine-local `[mcp_servers.<name>]` table. Servers added with `codex mcp add` belong there, not in the tracked template.

An absent `pi.subagent_model` entry intentionally inherits the main agent model. `enterprise-artifact.npm_registry` excludes the URL scheme. `voxtype-wsl-bridge.hold_key` must name a key the keyboard actually reports. `fcitx5.theme` must match an installed theme directory, including case.

#### Git Repo Identities

Configure `variables.git.repo_identities` in `.dotter/local.toml`; `git/config` and `jj/config.toml` render it. Each entry's leaf config is deployed from `git/generated/<key>.conf` to `~/.config/git/generated/<key>.conf`; apply the root-and-leaf ownership rules below.

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

#### TOML Template Tips

Put standalone control blocks in `# ` comments so TOML-aware editors still parse the raw template. Use `# ---` for a comment separator that must survive rendering.

- **Reduce redundant `#if` guards**: when `global.toml` provides an empty list/table default, use `#each` directly without an outer `#if` wrapper; `#each` produces zero items for an empty collection and does not error. Only use `#if` when the variable may be completely undefined (no global default).
- Combining `#if`+`#each` (and `/each`+`/if`) onto a single `# ` line reduces residual empty comment lines after rendering.
- Dotter treats any file containing `{{` as a template; `.tmpl` is not a required or special suffix.

Example: `codex/codex/config.toml`. Cleanup behavior is owned by [`.dotter/AGENTS.md`, Deploy Scripts](.dotter/AGENTS.md#deploy-scripts).

#### YAML Template Tips

Comment standalone Handlebars controls and quote inline scalar values, for example `repo: "{{repo}}"` and `- "{{this}}"`. Exception: preserve the target tool's unquoted form when reverse sync requires identical bytes, as in `glab/config.yml`. Example: `skm/skills.yaml`.

#### JSON Template Tips

JSON has no comments, so Handlebars control blocks split into two forms:

- **Standalone control blocks** (`{{#each}}`, `{{/each}}`, `{{#if}}`, `{{/if}}`) go on `# `-prefixed lines. Example: `enterprise-artifact/.docker/config.json`.
- **Inline control blocks** (e.g. `{{#unless @last}},{{/unless}}` for comma separation) stay bare, because they must emit literal characters and cannot be commented out.

Cleanup contract: [`.dotter/AGENTS.md`, Deploy Scripts](.dotter/AGENTS.md#deploy-scripts).

- **Use `@root.` for package-level variables inside `{{#each}}`**: `#each` makes each item the current context, so relative paths in helper arguments (e.g. `enterprise-artifact.user_id`) fail to resolve inside the loop and the whole expression **silently renders empty** (deploy does not error). Conditions on package-level variables fail the same way. Write `@root.enterprise-artifact.user_id` instead. Templates with only `#if` and no `#each` (e.g. `npm/.npmrc`) are unaffected because the root context is preserved. The same rule applies to `#each` loops in TOML and YAML templates (e.g. `{{#each skm.local_packages}}` referencing package-level variables).

## Live Config Reverse Sync Pattern

When an agent tool modifies its own config file at runtime (e.g., adding trusted folders, switching models), and the Dotter template renders from the same variable source, deploy will overwrite local changes. Solution: reverse-sync live config changes into `local.toml` before deploy, then let the template read from `local.toml`.

See `.dotter/AGENTS.md` for constraints on deploy scripts (POSIX sh, no literal `{{` in embedded code, runtime artifact conventions).

### Match the Tool's Serialization

A template and a tool that rewrites the same file are two writers of one file, so they drift as soon as their bytes differ: Dotter sees a changed target and refuses to deploy. The goal is a render that is byte-identical to what the tool writes, with reverse sync carrying the values.

- Reproduce the tool's own serializer, not a tidier layout: key order, indentation, and whether the key exists at all. An `omitempty` field means an empty collection renders as no key, not as `{}`.
- Render collections in the shape the tool writes them. Go's `encoding/json` sorts map keys and writes a non-empty map multi-line, so a one-line `{ ... }` never matches.
- Gate a collection key with `{{#if}}` so the empty and non-empty renders both match, and keep the control inline (`{ {{~#each ...}}`; `{{{` would parse as a triple-stash) so no `# ` residue line is emitted.
- Reverse-sync the values the tool writes back into `local.toml`, so the template renders what the tool last saved instead of a repo default.
- Keys the tool derives belong in neither the template nor `local.toml`; rendering a copy makes every deploy skip.

Example: `magpie/settings.json` pins `guideHidden` and `textSize` because magpie always writes them, renders `modelWires` only when non-empty because magpie omits an empty map, and leaves `modelCompacts` out entirely because magpie derives it.

### Local Schema Differences

When a variable is renamed or removed, update the tracked placeholder, template, and documentation to the new schema, but do not silently migrate, copy, or delete a legacy key in `local.toml`.

If a local schema still contains a legacy key, surface the difference and ask the user whether to keep, migrate, or remove it. Deploy and reverse-sync scripts must never make that choice automatically.

### Decision Framework: When to Add a Local Variable + Reverse Sync

Two sequential decisions: **should it be a local variable**, then **should it be reverse-synced**.

#### Step 1: Does it need a local variable?

Make a value a Dotter variable in `local.toml` (rather than hardcoding in the template or `global.toml`) when:

- **Differs across machines** — the same template must produce different results on different machines (e.g., enterprise model at work, public model at home)
- **Tool modifies at runtime** — the agent tool will change this value locally; the template must reflect the live value, not a repo default
- **Secrets and credentials** — never commit them; place them per Source Rules

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

1. **Declare the variable** — add its namespaced declaration and default in `.dotter/global.toml`.
1. **Reference in template** — render with `{{#each}}` / `{{#if}}` in the corresponding template
1. **Add sync function** — write a normalize-compare-write function in `live_config_reverse_sync.py`
1. **Register in main()** — call the sync function in the corresponding agent block

Normalization and synchronization patterns: `.dotter/scripts/live_config_reverse_sync.py` (`normalize_*`, `sync_*`, `main`).

## Commands

Deployment and conflict handling: [`.dotter/AGENTS.md`, Deploy Workflow](.dotter/AGENTS.md#deploy-workflow).
