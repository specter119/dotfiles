# Dotfiles Repository

Cross-platform dotfiles managed by [dotter](https://github.com/SuperCuber/dotter).
Dotter links each file individually; the repo is the source, the live machine is
the state.

## Read before editing

| If you touch | Read first |
| --- | --- |
| `.dotter/` deploy scripts, cache, helpers | `docs/maintenance/deploy.md` |
| package selection, `depends`, `[pkg.files]` | `docs/maintenance/config.md` |
| a template (`{{...}}`) or a variable | `docs/maintenance/templates.md` |
| reverse sync or a tool that rewrites its config | `docs/maintenance/live-state.md` |
| systemd units, session targets | `docs/maintenance/deploy.md#session-services` |
| Codex worktree adoption (`codex/codex/hooks.json`, `jj-adopt-worktree.sh`) | `docs/maintenance/codex-worktrees.md` |
| `AGENTS.md`, `README.md`, package docs | `AGENTS.md#documentation-ownership` |
| agent packages (`agent`, `droid`, `pi`, ...) | `agent/AGENTS.md` |

The table is the routing index. The review topology behind it is
`.agents/review-graph.toml`; run a stance review only when a change trades one
objective against another, not for an ordinary edit.

## Resident invariants

These hold without reading further; a change that breaks one is wrong even if
every surface check passes.

- Agent configs deploy under XDG (`~/.config/<name>`), not `~/.<name>`. Resolve
  paths from `.dotter/global.toml` and the owning `environment.d` fragment.
  A variable belongs to the package that owns the tool: it lives in
  `<pkg>/environment.d/<pkg>.conf`, nested under whichever source dir maps to
  `~/.config`. Only a tool without its own package keeps its variables in
  `agent/config/environment.d/agentic-xdg.conf`.
- Never commit a secret. Use inline `rbw get`; keep `local.toml` out of git.
- Enterprise CA/TLS settings are gated by `dotter.packages.enterprise-artifact`
  or the variable that makes them meaningful. A non-enterprise machine deploys
  none.
- `depends` is for grouping or functional coupling, never for a variable
  reference. Test selection with `dotter.packages.<name>`, variables with `#if`.
- Variables are namespaced under `[pkg.variables.pkg]`; strict mode requires the
  template path `pkg.var_name` to match the definition path.
- One mapping per target root; Dotter links per file. Do not split a shared
  prefix into exact-file mappings.
- A template that a tool also writes must render byte-identical to the tool's
  serializer. Reverse-sync live values into `local.toml` instead of forcing.
- A Dotter control block stands on its own line; never prefix it with the
  format's comment marker.
- Do not edit `.dotter/cache.toml`; it is Dotter's state.
- Do not commit, push, or change branch strategy unless asked.

## Documentation ownership

One fact, one owner. `README.md` is user-facing; `AGENTS.md` and
`docs/maintenance/` are implementation contracts; a package `README.md` only
when the package maps its own target directory or is not deployed. Do not
duplicate a rule into a second document; link it.

A package README is allowed only when its layout is not self-evident and it
does not land in a shared target. A package-root mapping into a shared target
(for example `sway = '~/.config'`) is documented here instead.

## Review topology

Stances: portability, live state, explicit composition, low friction, enterprise
isolation, shared default. Axes: `portability-vs-live-state`,
`explicit-vs-friction`, `isolation-vs-sharing`. Registry:
`.agents/skills/dotfiles-stance-registry/SKILL.md`. Graph and passes:
`.agents/review-graph.toml` and `.agents/reviews/`.

Route before assigning a stance reviewer; the graph selects surfaces and axes,
not a verdict. Do not average an unresolved conflict; record it as a decision
or an unrepresented stake. Decisions live in the maintenance docs and the
graph's `[[decision]]` rows, each with a reopen condition.

```sh
HYDRA=~/.local/share/skm/skills/github.com_specter119_hydra-crux/skills/hydra-crux
python3 "$HYDRA/scripts/hydra_graph.py" --graph .agents/review-graph.toml route --changed <path> --format markdown
python3 "$HYDRA/scripts/hydra_graph.py" --graph .agents/review-graph.toml generate
python3 "$HYDRA/scripts/hydra_graph.py" --graph .agents/review-graph.toml lint
```

`prek` runs the same lint through the `hydra-crux-lint` hook. A pass is a draft
under `.agents/reviews/`; bind it with `route --pass <slug>`, then record the
ledger. Lint checks structure, not whether a stance or surface prose is sound.
