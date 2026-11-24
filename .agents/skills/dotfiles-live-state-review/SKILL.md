---
name: dotfiles-live-state-review
description: >-
  Use when reviewing reverse sync, tool-written config serialization, a deploy
  conflict, or a local schema difference. Do not use for package composition or
  deploy scripts.
---

# Live state review

## Scope

Reverse sync, byte-identical serialization, local schema differences, and the
deploy conflict path for tool-written config.

## Checks

- `pre_deploy.sh` runs `live_config_reverse_sync.py` before templates render.
- The sync function normalizes, compares, and writes only changed values into
  `local.toml`; it does not write a repo default over an observed live value.
- A template that a tool also writes reproduces the tool's serializer: key
  order, indentation, `omitempty`, sorted maps, and collection shape.
- Keys the tool derives are in neither the template nor `local.toml`.
- A renamed or removed variable does not silently migrate, copy, or delete a
  legacy key; the difference is surfaced to the user.
- A dry-run after the sync shows no drift.

## Required evidence

The live file before and after, the sync function's normalize/compare/write
path, and a dry-run that shows no drift.

## Owner documents

- `docs/maintenance/live-state.md`
- `docs/maintenance/deploy.md#deploy-workflow`

## Does not own

- Portability of the tracked template: `dotfiles-portability-stance`
- Package selection and mappings: `dotfiles-config-composition-review`
