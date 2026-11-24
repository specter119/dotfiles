# Packages and mappings

Dotter packages are a layered grouping system, not a flat list of folders.

- **Base packages** hold one tool or concern's payload.
- **Composing packages** select base packages so one choice deploys a whole
  environment.
- Agent grouping is nested: `agent` is the shared entry, `agent-tunnel` holds
  remote/service integrations, `agent-runtime` holds local runtime support.

`enterprise-artifact` is the single source of enterprise Artifactory
credentials and registry endpoints. A deployment without it must stay valid, so
consumers test `dotter.packages.enterprise-artifact` instead of depending on it.

## Package composition

`depends` expresses a deployment relationship, never a variable reference. Use
it for exactly two reasons:

- **Grouping**: one selection deploys a whole environment with fewer decisions.
- **Functional coupling**: the dependent software cannot work without the
  dependency's deployed payload.

Reading another package's variable, or testing `dotter.packages.<name>`, is not
a dependency. A template that guards such a value with `#if` has two valid
renderings and deploys either way, so it must not declare `depends`. Add
`depends` for a variable only when the dependent has no working form once the
variable is removed.

When changing package names, dependencies, or file mappings, preserve the
layered relationship unless the change is explicitly a package-architecture
refactor.

Checks and evidence live in
`.agents/skills/dotfiles-config-composition-review/SKILL.md`.

## Files mapping

A mapping pairs a source root with a target root. Dotter links every file under
it individually, so a mapping never owns a directory as a unit.

- Give each target root one mapping and minimize entries in the global mapping
  table.
- Do not split a shared prefix into exact-file mappings.
- Add another mapping only when the target root or the mapping semantics
  (`type`, `if`) differ.
- Because links are per file, retiring one file means deleting the source file
  and deploying once. Until Dotter drops the stale symlink, the tool writes
  through it back into the repository.

```toml
# one mapping; Dotter creates a symlink per file, including subdirectories
package = '~/.config/package'
```

```toml
# wrong: two mappings for one target root
'package/config.toml' = '~/.config/package/config.toml'
'package/subdir/file.toml' = '~/.config/package/subdir/file.toml'
```

To retire a file, delete its source and run a dry-run deploy. Dotter reports the
target it would remove; confirm the target is not a live file another tool owns
before accepting the removal.

## Conditional configuration

Configuration that must exist only when a package is selected or a variable is
set stays out of the unconditional path. Prefer **conditional deploy** over
**conditional context**:

1. **Conditional deploy** (preferred): put the conditional part in its own
   source directory and gate its mapping in the owning package:

   ```toml
   'wsl-guest-enterprise' = { target = '~/.config', if = 'dotter.packages.enterprise-artifact' }
   ```

   Name the directory `<package>-<condition>`; it is a source directory, not a
   Dotter package. Use it whenever the target tool reads a drop-in or include
   location (`environment.d/`, `<unit>.d/`, `config.d/`, `*.d/`), so the base
   file carries no condition. Directory mappings into the same target coexist
   because Dotter links per file.

2. **Conditional context** (fallback): an `#if` inside the template. Use it only
   when the target is one file with no drop-in or include mechanism (for example
   `uv.toml`), or when the conditional value is interleaved with unconditional
   keys of the same structure.

Confirm in the tool's documentation that it reads the drop-in location before
choosing conditional deploy. If you cannot confirm it, use conditional context
and record why.

Test package selection with `dotter.packages.<name>` and variables with `#if`,
never with `depends`.

## Enterprise boundary

`enterprise-artifact` owns the credentials and registry endpoints. Enterprise
trust settings are separate and must be gated:

- Anything that trusts a non-default CA or relaxes verification
  (`NODE_USE_SYSTEM_CA`, `NODE_EXTRA_CA_CERTS`, `--use-openssl-ca`,
  `system-certs`, `ssl_verify`, and the like) is gated by
  `dotter.packages.enterprise-artifact` or by the variable that makes the
  setting meaningful (`enterprise_proxy.url`, `raft.server_url`).
- A machine outside the enterprise group deploys none of them unless such a
  variable is set.
- Prefer a conditional source directory (`wsl-guest-enterprise/`,
  `condarc-enterprise/`) over an `#if` in the base file. See
  `#conditional-configuration`.

`enterprise-artifact.npm_registry` excludes the URL scheme. Do not turn
`~/.config/magpie/providers.json` or the agent-side model data derived from it
into a Dotter template or reverse-sync target; magpie owns that artifact.
