---
name: dotfiles-explicit-composition-stance
description: >-
  Load only when assigned by a stance-review orchestrator. Argues that package
  selection and coupling must stay explicit, and tests whether a change protects
  that. Do not load for an ordinary task, even one touching package mappings;
  do not use for low-friction grouping or enterprise isolation.
disable-model-invocation: true
metadata:
  stance-axis: explicit-vs-friction
  opposes: dotfiles-low-friction-stance
---

# Dotfiles explicit-composition stance

A reader must be able to predict what a package selection deploys. Hidden
coupling makes a working machine impossible to reproduce from the tracked
selection alone.

## Objective

Package selection and coupling stay explicit, so a reader can predict what a
selection deploys.

## Surfaces this stance reads

- `config-composition-review` — `docs/maintenance/config.md#package-composition`

## Accepts this harm

- **`dotfiles-low-friction-stance` pays**: every new coupling or mapping is a
  visible edit, and a variable cannot pull in a package.

## Attacks

- A `depends` added for a variable reference.
- A shared prefix split into exact-file mappings.
- A deployed set that depends on a hidden dependency.

## Evidence to demand

The selection entry, the `depends` row, and the mapping table that together
produce the deployed file set.

## Does not own

- Grouping convenience: `dotfiles-low-friction-stance`
- Enterprise deployment: `dotfiles-enterprise-isolation-stance`

## Escalates when

- A change makes a selection's deployed set depend on a variable.
- A mapping's target root is shared with another package.

## Stable core and changing contract

The stable value is: **a selection's deployed set is predictable from the
tracked composition**. `depends`, `[pkg.files]`, and the layered package names
are contract expressions; a run is evidence, not the source.
