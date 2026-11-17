---
name: dotfiles-enterprise-isolation-stance
description: >-
  Load only when assigned by a stance-review orchestrator. Argues that enterprise
  trust and credentials must stay opt-in and single-sourced, and tests whether a
  change protects that. Do not load for an ordinary task, even one touching
  enterprise files; do not use for shared defaults or live-state preservation.
disable-model-invocation: true
metadata:
  stance-axis: isolation-vs-sharing
  opposes: dotfiles-shared-default-stance
---

# Dotfiles enterprise-isolation stance

A machine outside the enterprise must never trust an enterprise CA, use an
enterprise registry, or carry an enterprise credential. Isolation is a security
boundary, not a convenience toggle.

## Objective

Enterprise trust and credentials are opt-in and single-sourced.

## Surfaces this stance reads

- `config-composition-review` — `docs/maintenance/config.md#package-composition`
- `enterprise-boundary-review` — `docs/maintenance/config.md#enterprise-boundary`

## Accepts this harm

- **`dotfiles-shared-default-stance` pays**: an enterprise machine needs
  separate conditional directories and variables.
- **The non-enterprise user pays**: the base config carries gating logic and
  must prove it deploys nothing.

## Attacks

- A CA/TLS setting in an unconditional file.
- A credential duplicated outside `enterprise-artifact`.
- An enterprise registry endpoint hardcoded in a base template.
- A non-enterprise machine that deploys an enterprise trust file.

## Evidence to demand

The `if` or variable gate, the deployed path on a non-enterprise selection, and
the single owner of the credential.

## Does not own

- Shared-default value: `dotfiles-shared-default-stance`
- Live-value survival: `dotfiles-live-state-stance`

## Escalates when

- A non-enterprise machine needs an enterprise-only trust setting.
- A new credential has no single owner.

## Stable core and changing contract

The stable value is: **no enterprise trust or credential deploys outside the
enterprise selection**. `enterprise-artifact`, the conditional source
directories, and the `if` gates are contract expressions. When the contract
changes, prove the non-enterprise render contains none of them.
