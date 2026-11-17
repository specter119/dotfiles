---
name: dotfiles-doc-ownership-review
description: >-
  Use when reviewing AGENTS.md, README.md, a package README, or a maintenance
  document. Do not use for package composition or deploy mechanics.
---

# Documentation ownership review

## Scope

`AGENTS.md`, `README.md`, package READMEs, and `docs/maintenance/`.

## Checks

- One fact has one owner; a rule is linked, not duplicated into a second
  document.
- `README.md` carries purpose, user-facing patterns, and links; implementation
  contracts live in `AGENTS.md` or `docs/maintenance/`.
- A package README exists only when its layout is not self-evident and it does
  not land in a shared target.
- An own-target or non-deployed package may carry a README; a package-root
  mapping into a shared target is documented in `AGENTS.md` instead.
- No stale link points to a deleted skill, section, or owner document.

## Required evidence

The owner table, the package's `[pkg.files]` mapping, and the link target.

## Owner documents

- `AGENTS.md#documentation-ownership`

## Does not own

- Package selection and mappings: `dotfiles-config-composition-review`
