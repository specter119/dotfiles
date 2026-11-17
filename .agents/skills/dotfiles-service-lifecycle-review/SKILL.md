---
name: dotfiles-service-lifecycle-review
description: >-
  Use when reviewing a systemd user unit, a session target, compositor
  autostart, or an output hook. Do not use for deploy scripts, package
  composition, or documentation ownership.
---

# Graphical-session service lifecycle review

## Scope

Systemd user units, `graphical-session.target`, `sway-session.target`,
compositor autostart, and output hooks.

## Checks

- A graphical-session service uses `PartOf=` and `After=graphical-session.target`.
  Only a service that calls sway (`swayidle`) belongs to `sway-session.target`.
- A default service carries no `[Install]`. Its package ships
  `systemd/user/<target>.d/10-<unit>.conf` with `[Unit] Wants=<unit>`.
- An opt-in service keeps `[Install]` and ships no drop-in.
- Sway imports the compositor environment, starts `sway-session.target`, and
  stops it on exit. The login wrapper does not start the target itself.
- An extension points from the plugin to the host through the host's drop-in
  directory. The host never names its plugins.
- A socket-activated service brings the daemon through `default.target.d/` and
  the socket through `sockets.target.d/`.

## Required evidence

The unit, the drop-in, the target, `systemctl --user cat`, and the journal for
the session.

## Owner documents

- `docs/maintenance/deploy.md#session-services`
- `docs/maintenance/deploy.md#session-targets`
- `docs/maintenance/deploy.md#service-defaults`
- `docs/maintenance/deploy.md#extensions`

## Does not own

- Deploy scripts and cache: `dotfiles-deploy-operations-review`
- Package selection and mappings: `dotfiles-config-composition-review`
- Documentation ownership: `dotfiles-doc-ownership-review`
