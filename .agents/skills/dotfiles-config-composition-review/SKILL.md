---
name: dotfiles-config-composition-review
description: >-
  Use when reviewing package selection, grouping, depends, a [pkg.files]
  mapping, a machine include, a blackhole mapping, or a conditional source
  directory. Do not use for template rendering, reverse sync, or enterprise
  trust scope.
---

# Package composition and mapping review

## Scope

Package selection, grouping, `depends`, `[pkg.files]` mappings, machine
includes, blackhole mappings, and conditional source directories.

## Checks

- A package is either a base package (one tool or concern's payload) or a
  composing package (selects base packages), not both.
- `depends` is only grouping or functional coupling. Reading another package's
  variable, or testing `dotter.packages.<name>`, is not a dependency. A
  template that guards such a value with `#if` has two valid renders and must
  not declare `depends`.
- Each target root has one mapping. A shared prefix is not split into
  exact-file mappings.
- A conditional part lives in a `<package>-<condition>` source directory and is
  gated by `if`. `#if` is used only when the target has no drop-in or include
  location, or the conditional value is interleaved with unconditional keys.
- A blackhole mapping points at
  `$XDG_RUNTIME_DIR/dotter/blackhole-<package>`, and the real live owner is
  documented next to the mapping.
- `enterprise-artifact` is not a hard dependency. Consumers test
  `dotter.packages.enterprise-artifact` and stay valid without it.
- A package README follows the own-target or non-deployed rule; a shared-target
  package is documented in the root `AGENTS.md`.

## Required evidence

The `[pkg.files]` mapping, the package's `depends`, the machine include, and
the target tool's drop-in or include documentation.

## Owner documents

- `docs/maintenance/config.md#package-composition`
- `docs/maintenance/config.md#files-mapping`
- `docs/maintenance/config.md#conditional-configuration`
- `docs/maintenance/config.md#blackhole-mapping`

## Does not own

- Template rendering, variables, and secrets: `dotfiles-config-rendering-review`
- Reverse sync and serialization: `dotfiles-live-state-review`
- Enterprise trust scope: `dotfiles-enterprise-boundary-review`
- Documentation ownership: `dotfiles-doc-ownership-review`
