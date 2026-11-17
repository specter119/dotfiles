---
name: dotfiles-config-rendering-review
description: >-
  Use when reviewing a template, a variable declaration or override, a secret
  injection, a git identity, or a root-and-leaf config. Do not use for package
  selection, reverse sync, or deploy scripts.
---

# Template, variable, and secret review

## Scope

Handlebars templates, variable declarations and overrides, secret injection,
git identities, and root-and-leaf config.

## Checks

- A variable is namespaced as `[pkg.variables.pkg]` in `global.toml` and
  overridden from top-level `[variables]` in `local.toml`.
- Inside `#each`, package-level variables use `@root.<namespace>.<name>`;
  relative paths silently render empty.
- A standalone Handlebars control sits on a bare line. An inline control stays
  inline with the value it terminates. No `# {{#if}}` residue reaches the
  target.
- TOML, YAML, and JSON quoting follows the target tool's serializer. `#if` is
  omitted when `#each` over an empty default already produces zero items.
- A secret uses inline `rbw get` or a local variable; no secret enters the
  tracked tree. Public client credentials are the documented exception.
- A git identity uses the default inline config, an enterprise leaf gated by
  `git.enterprise`, and one `includeIf` per platform path form.
- A root-and-leaf config has a tracked fixed leaf or a pre-deploy generator for
  a dynamic leaf. Only a runtime leaf is reverse-synced.

## Required evidence

The rendered bytes, the variable declaration and local override, the `rbw`
command, and the target tool's serializer or quoting rules.

## Owner documents

- `docs/maintenance/templates.md#template-rendering`
- `docs/maintenance/templates.md#variable-schema`
- `docs/maintenance/templates.md#source-rules`
- `docs/maintenance/templates.md#secret-injection`
- `docs/maintenance/templates.md#git-identities`
- `docs/maintenance/templates.md#root-and-leaf`

## Does not own

- Package selection and mappings: `dotfiles-config-composition-review`
- Reverse sync and serialization: `dotfiles-live-state-review`
- Enterprise trust scope: `dotfiles-enterprise-boundary-review`
