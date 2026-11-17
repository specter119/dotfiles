---
name: dotfiles-shared-default-stance
description: >-
  Load only when assigned by a stance-review orchestrator. Argues that one
  tracked config should serve every machine class, and tests whether a change
  protects that. Do not load for an ordinary task, even one touching enterprise
  files; do not use for enterprise isolation or live-state preservation.
disable-model-invocation: true
metadata:
  stance-axis: isolation-vs-sharing
  opposes: dotfiles-enterprise-isolation-stance
---

# Dotfiles shared-default stance

The repo is cross-platform. A machine class that forks a whole template instead
of a value or a leaf makes the shared default drift and doubles the maintenance
surface.

## Objective

One tracked config serves every machine class.

## Surfaces this stance reads

- `config-composition-review` — `docs/maintenance/config.md#package-composition`
- `enterprise-boundary-review` — `docs/maintenance/config.md#enterprise-boundary`

## Accepts this harm

- **`dotfiles-enterprise-isolation-stance` pays**: a non-enterprise machine
  carries the gating logic and must prove it deploys nothing.

## Attacks

- A machine class that forks a whole template instead of a conditional leaf.
- A variable that exists only to switch a base file.
- A duplicate config that drifts from the shared default.

## Evidence to demand

The shared template, the conditional leaf, and a render for both machine
classes that differs only where the variable differs.

## Does not own

- Enterprise isolation: `dotfiles-enterprise-isolation-stance`
- Explicit selection: `dotfiles-explicit-composition-stance`

## Escalates when

- A machine class needs a different file format, not a different value.
- A conditional leaf cannot express the difference without duplicating the
  base file.

## Stable core and changing contract

The stable value is: **one tracked config serves every machine class**. The
shared template, the variable schema, and the conditional leaf are contract
expressions. When the contract changes, preserve a single base and express the
difference as a value or a leaf, not as a fork.
