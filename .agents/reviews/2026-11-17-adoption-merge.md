+++
status = "record"
target = "merge master into the v2 adoption and absorb new maintenance docs"
changed = [".agents/review-graph.toml", ".agents/skills/dotfiles-deploy-operations-review/SKILL.md", ".dotter/global.toml", ".dotter/post_deploy.sh", ".dotter/scripts/live_config_reverse_sync.py", "AGENTS.md", "codex/codex/config.toml", "codex/codex/hooks.json", "codex/codex/scripts/jj-adopt-worktree.sh", "docs/maintenance/deploy.md", "docs/maintenance/live-state.md", "docs/maintenance/templates.md", "droid/config/mcp.json", "droid/config/settings.json", "fcitx5/fcitx5/conf/notifications.conf", "fcitx5/fcitx5/profile", "pi/mcp.json", "pi/settings.json", "prek.toml", "rclone/README.md", "rclone/bin/rclone-zotero-sync", "rclone/bin/rclone-zotero-watch", "rclone/config/rclone.conf", "rclone/systemd/user/rclone-bisync-zotero.service", "rclone/systemd/user/rclone-bisync-zotero.timer", "rclone/systemd/user/rclone-watch-zotero.service"]
baseline = {".agents/review-graph.toml" = "dccbee9697fc70efce46edce019193e74eecebb7", ".agents/skills/dotfiles-deploy-operations-review/SKILL.md" = "dd4fa87c666655fef1691ace5b4c3cfc80c87ed7", ".dotter/global.toml" = "5c796886a4349e4692abd6406dfff4c7764bbace", ".dotter/post_deploy.sh" = "887a3c0920d90efc0d9140345f13236c6cb3072a", ".dotter/scripts/live_config_reverse_sync.py" = "0e8b7705a71f07f3de2268a4b1133197a65bf1b8", "AGENTS.md" = "f3ef5ae775d4b6bdb2a5fc6e69345a83583c99d3", "codex/codex/config.toml" = "88eb8f353cea316e166f3c7beeb2bb7fb73d32c1", "codex/codex/hooks.json" = "d531945bfe4a0272e0dec70613da6eb576993b0f", "codex/codex/scripts/jj-adopt-worktree.sh" = "6ed9489e385caae9ae6112a2bfa582c62b5026b3", "docs/maintenance/deploy.md" = "83c7978da8054fdebd3a2d083a7c6102d6b8ba50", "docs/maintenance/live-state.md" = "0552c72def0846d5d456a391a027e5d8e7159975", "docs/maintenance/templates.md" = "18e2bbba768ba66437e5a2ac277cc975501b4be3", "droid/config/mcp.json" = "d523e44fd63dc28e904f3cb5990399fbdaf7bc5f", "droid/config/settings.json" = "20cb7b1cf38f32033e908c4a8550376e057f5242", "fcitx5/fcitx5/conf/notifications.conf" = "6375a909a9cc79518a05ff95523e93b3f39336dc", "fcitx5/fcitx5/profile" = "a7dabfd9156a1fc2140eece54e49242c4ce9a7f6", "pi/mcp.json" = "ef5fe39e71321f0a294eaf095738e15a47ff9778", "pi/settings.json" = "0dedf10a16c2a835cc7a3e918d73ff624447ab47", "prek.toml" = "ae9d1746e510c8b1dd11c4139ede4f756facdc06", "rclone/README.md" = "9a60d4d3bfa34597669da33b809655bde4464876", "rclone/bin/rclone-zotero-sync" = "b99f5bfd35cfba5e1766d3a012cf67283311cb61", "rclone/bin/rclone-zotero-watch" = "b72e4006890a6467fc2fd48858c8636d573b885d", "rclone/config/rclone.conf" = "72e28e3821c34779e5d142793c3f0cddb874e7f0", "rclone/systemd/user/rclone-bisync-zotero.service" = "7bcf5c60c3f7c48d25ef0f088b03a5a8dbf7a39f", "rclone/systemd/user/rclone-bisync-zotero.timer" = "55837da4422aaee27ec544a59e6771f67bf5d17a", "rclone/systemd/user/rclone-watch-zotero.service" = "4cdcd63b6b61296095899059e4296270cd95a272"}
dirty_at_bind = {}
axes = ["explicit-vs-friction", "isolation-vs-sharing", "portability-vs-live-state"]
stances = ["dotfiles-enterprise-isolation-stance", "dotfiles-explicit-composition-stance", "dotfiles-live-state-stance", "dotfiles-low-friction-stance", "dotfiles-portability-stance", "dotfiles-shared-default-stance"]
included = []
skipped = []
decisions = ["D1-reverse-sync", "D2-serializer-fidelity", "D3-conditional-deploy", "D4-depends-restriction", "D5-enterprise-gating", "D6-one-mapping-per-root", "D7-package-readme", "D8-new-tool-serializer"]
reason = ""
rebaselined = []
+++
## Findings

- `master` added four commits after the adoption base: Codex managed-worktree
  adoption, droid/pi MCP and model-default updates, and the rclone Zotero sync
  package.
- No new stance or axis. The 6-stance / 3-axis set still matches the migration
  probe and the adoption graph.
- New documentation to absorb: Codex worktree adoption, the rclone variable
  contract, the reverse-sync single-pass detail, and `rclone/README.md`.
- Two conflicts: `.dotter/AGENTS.md` was deleted by the adoption and modified by
  master; `AGENTS.md` was rewritten by the adoption and extended by master.
  Resolution kept the deletion and the slim `AGENTS.md`, then moved the new
  content into `docs/maintenance/`.

## Ledger

- Kept `.dotter/AGENTS.md` deleted. Absorbed its new reverse-sync detail into
  `docs/maintenance/live-state.md#implementation`: Dotter loads `local.toml`
  before the hook, so the first deploy skips a changed target and the next
  converges; `uv run .dotter/scripts/live_config_reverse_sync.py && dotter
  deploy` converges in one pass.
- Added `docs/maintenance/deploy.md#codex-worktrees` for the `SessionStart`
  hook, the no-op conditions, the mid-session limitation, and the colocated jj
  choice. Added a routing row in `AGENTS.md`.
- Added the rclone variable contract to
  `docs/maintenance/templates.md#variable-declarations`: client id/secret and
  `zotero_remote` are user-maintained; `dropbox.token` is reverse-synced because
  rclone rotates it.
- Added `rclone/config/rclone.conf` to `live-state-review` paths. Added
  `codex/codex/hooks.json` and `codex/codex/scripts/**` to
  `deploy-operations-review` paths, plus a check that the hook stays a no-op
  outside a managed worktree.
- Merged `prek.toml`: kept the `hydra-crux-lint` hook, took master's
  `toml-sort` `v0.26.0` and the `rclone/config/rclone.conf` end-of-file
  exclusion.
- `rclone/README.md` is a new package README and routes through
  `doc-ownership-review`; its systemd units route through
  `service-lifecycle-review`.
- Verified: `generate`, `lint`, `prek`, relative-link check, and
  `git diff --check` after conflict resolution.

Unproven:

- No real `dotter deploy` or rclone cold-start trial in this session.
- The Codex worktree hook was not exercised in a live Codex session; only its
  script and doc were merged.
- The main worktree has uncommitted fcitx5 changes on the same files master
  changed. The merge back to `master` must not clobber them.

## Map candidates

- The Codex worktree adoption script now routes through
  `deploy-operations-review` because the hook is runtime glue. If it grows
  beyond a single no-op guard, give agent-runtime hooks their own surface rather
  than stretching the deploy checks.
- `rclone/bin/*` are package binaries, not deploy scripts. They are documented
  by `rclone/README.md`; if they gain a maintenance contract, add a
  package-runtime check rather than a new stance.
- `agent/AGENTS.md:21` still carries the `pull capability hint` vs `push
  control-flow duty` axis. It is outside the dotfiles deployment graph; keep it
  as a separate agent-config topology candidate.

## Counterexample candidates

- A green `lint` still does not prove semantic soundness. The migration probe's
  injected surface verdict was not flagged by `concept_audit.py`; lint only
  checks structure.
- Enabling reverse sync for a new tool before observing its writer twice would
  be a counterexample to D1 and the D8 open decision. The rclone token is
  reverse-synced only because rclone rotates it; do not generalize that to every
  rclone key.
