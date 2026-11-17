---
name: dotfiles-portability-stance
description: >-
  Load only when assigned by a stance-review orchestrator. Argues that a tracked
  config must render correctly on every selected machine, and tests whether a
  change protects that. Do not load for an ordinary task, even one touching
  package mappings or reverse sync; do not use for live-state preservation or
  enterprise isolation.
disable-model-invocation: true
metadata:
  stance-axis: portability-vs-live-state
  opposes: dotfiles-live-state-stance
---

# Dotfiles portability stance

A dotfiles repo is only useful if a fresh machine can select packages and get a
working config without hand-editing tracked files. This project pays for that by
keeping machine differences in `local.toml` and conditional mappings, not in the
templates.

## Objective

A tracked config renders correctly on every selected machine without a manual
rescue.

## Surfaces this stance reads

- `live-state-review` — `docs/maintenance/live-state.md`

## Accepts this harm

- **`dotfiles-live-state-stance` pays**: a live value must be carried back into
  `local.toml` before it can render.

## Attacks

- A machine difference that only a manual edit can supply.

## Evidence to demand

The surface's required evidence: `docs/maintenance/templates.md#required-evidence`.

## Does not own

- Live-value survival: `dotfiles-live-state-stance`
- Enterprise deployment: `dotfiles-enterprise-isolation-stance`

## Escalates when

- A change makes a tracked file depend on a value that cannot be expressed in
  `local.toml`.
- A new machine class needs a branch that the current variable schema cannot
  represent.

## Stable core and changing contract

The stable value is: **a tracked config renders on every selected machine**.
`global.toml`, `local.toml`, conditional mappings, and the blackhole target are
contract expressions, not the value itself.
