---
name: dotfiles-live-state-stance
description: >-
  Load only when assigned by a stance-review orchestrator. Argues that a tool's
  live config must survive deploy, and tests whether a change protects that. Do
  not load for an ordinary task, even one touching reverse sync; do not use for
  portability or enterprise isolation.
disable-model-invocation: true
metadata:
  stance-axis: portability-vs-live-state
  opposes: dotfiles-portability-stance
---

# Dotfiles live-state stance

The live machine is where the user actually works. A tool that rewrites its own
config is expressing a real local choice; a deploy that overwrites it loses
work, even when the tracked template is "correct".

## Objective

A tool's live config survives deploy and is not silently overwritten.

## Surfaces this stance reads

- `live-state-review` — `docs/maintenance/live-state.md`

## Accepts this harm

- **`dotfiles-portability-stance` pays**: a fresh machine may render differently
  until `local.toml` is populated, and deploy can block on a conflict.
- **The user who switched a setting in the tool UI pays**: the switch is lost
  if reverse sync does not cover the key.

## Attacks

- A force deploy over a live change.
- A template that renders a default over a key the tool wrote.
- A sync function that writes a repo default instead of the observed live value.
- A schema migration that silently deletes a legacy key in `local.toml`.

## Evidence to demand

The surface's required evidence: `docs/maintenance/live-state.md#required-evidence`.

## Does not own

- Portability: `dotfiles-portability-stance`
- Enterprise deployment: `dotfiles-enterprise-isolation-stance`

## Escalates when

- A tool rewrites a config with no stable serializer.
- A live value has no variable path, so the only options are overwrite or
  hand-edit.

## Stable core and changing contract

The stable value is: **a live tool value survives deploy**. The sync script,
`local.toml`, and the per-tool `sync_*` functions are contract expressions. When
the contract changes, preserve the observed value and the conflict signal; do
not replace them with a default.
