---
name: dotfiles-low-friction-stance
description: >-
  Load only when assigned by a stance-review orchestrator. Argues that one
  package selection should deploy a whole environment with few decisions, and
  tests whether a change protects that. Do not load for an ordinary task, even
  one touching package mappings; do not use for explicit composition or
  enterprise isolation.
disable-model-invocation: true
metadata:
  stance-axis: explicit-vs-friction
  opposes: dotfiles-explicit-composition-stance
---

# Dotfiles low-friction stance

A dotfiles repo that requires ten selections to reach a usable environment is
not maintainable. Grouping packages exist so one choice deploys a coherent
environment.

## Objective

One package selection deploys a whole environment with few maintainer
decisions.

## Surfaces this stance reads

- `config-composition-review` — `docs/maintenance/config.md#package-composition`

## Accepts this harm

- **`dotfiles-explicit-composition-stance` pays**: a grouping package hides
  which base package supplies a file.

## Attacks

- A mapping that forces a per-file decision.
- A dependency graph so flat that one environment needs ten selections.

## Evidence to demand

The selection a user would run, the packages it pulls in, and the files that
would be missing without the grouping.

## Does not own

- Hidden-coupling acceptability: `dotfiles-explicit-composition-stance`
- Package portability: `dotfiles-portability-stance`

## Escalates when

- A new environment needs more than one selection to be usable.
- A grouping package cannot express a required coupling without a hidden
  dependency.

## Stable core and changing contract

The stable value is: **one selection reaches a usable environment**. The
composing package, its `depends` list, and the environment groups are contract
expressions.
