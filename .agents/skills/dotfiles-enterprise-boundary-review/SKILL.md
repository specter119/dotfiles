---
name: dotfiles-enterprise-boundary-review
description: >-
  Use when reviewing enterprise credentials, CA/TLS trust, registry endpoints,
  or proxy settings. Do not use for shared defaults or live-state reconciliation.
---

# Enterprise boundary review

## Scope

Enterprise credentials, CA/TLS trust, registry endpoints, and proxy settings in
this dotfiles tree.

## Checks

- Anything that trusts a non-default CA or relaxes verification is gated by
  `dotter.packages.enterprise-artifact` or by the variable that makes the setting
  meaningful (`enterprise_proxy.url`, `raft.server_url`).
- A machine outside the enterprise group deploys none of those settings unless
  such a variable is set.
- `enterprise-artifact` is the single source of enterprise credentials and
  registry endpoints; no second copy exists.
- Enterprise-only files live in a conditional source directory
  (`wsl-guest-enterprise/`, `condarc-enterprise/`) rather than an unconditional
  base file.

## Required evidence

The `if` or variable gate, a non-enterprise render that contains none of the
enterprise trust, and the single owner of each credential.

## Owner documents

- `docs/maintenance/config.md#enterprise-boundary`
- `docs/maintenance/templates.md#source-rules`

## Does not own

- Shared-default value: `dotfiles-shared-default-stance`
- Live-value survival: `dotfiles-live-state-stance`
