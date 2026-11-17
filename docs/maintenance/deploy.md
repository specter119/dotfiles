# Deploy

Scope: `.dotter/` scripts, cache, helpers, runtime artifacts, and the systemd
units they reload.

## Deploy workflow

1. Run `dotter deploy --dry-run --verbose` and read the diff.
2. A conflict means the live file changed. Extract the value into a variable or
   accept the live value.
3. `--force` is the last resort and needs the user's explicit approval.

Do not edit `.dotter/cache.toml` or `.dotter/cache/`; they are Dotter's state.
A dry run may read them.

## Scripts

`pre_deploy.sh` runs reverse sync, then `rbw sync`, so templates and post-deploy
scripts see current vault data. `post_deploy.sh` reloads systemd, refreshes
magpie artifacts, audits prek parser coverage, and fixes permissions. Both are
POSIX `sh`; call a Bash-only helper explicitly with `bash ...`.

- No literal `{{` in embedded code; Dotter would parse it as a template.
- Do not post-process a rendered template to remove residue. Fix the template.
- Do not write secrets or tool-generated runtime state from a post-deploy
  script into a repo-managed config.
- `pre_deploy.sh` does not depend on `enterprise-artifact` variables; registry
  credentials stay in that package.
- Keep the scripts idempotent: a second run must not change a correct artifact.

## Runtime artifacts

Runtime artifacts are owned by the tool that writes them. `post_deploy.sh`
refreshes the magpie provider/model artifacts and the derived agent catalogs;
the refresh functions live in `.dotter/scripts/`. Do not turn these artifacts
into templates or reverse-sync the provider list.

- `republish_magpie_settings` renames the rendered `magpie/settings.json` into
  place: magpie reads that file while it runs and must never see a truncated
  one.
- `refresh_magpie_codex_catalog` writes `~/.config/codex/magpie-models.json`
  from the gateway, not from `magpie codex`: that command rewrites the
  Dotter-owned `config.toml`.
- `refresh_magpie_pi_models` runs `magpie pi` with the model Dotter just
  rendered, so magpie leaves `pi/settings.json` byte-equal; any other model
  makes it rewrite the file and the next deploy refuses it. The responses
  normalization must follow every `magpie pi` run, because magpie rewrites
  `models.json` each time.
- `refresh_magpie_dsh_models` runs `magpie dsh` with `dsh.default_model`, then
  puts the provider back on the Anthropic wire: magpie owns the model list, the
  wire is ours.
- The refresh steps warn and keep the previous artifact when they fail. Route,
  format, and normalization details live in the script comments.
- Runtime artifacts are deploy-time files under `$XDG_RUNTIME_DIR/dotter/`:
  prefer writing one there from `.dotter/pre_deploy.sh` when several templates
  need the same derived value, and treat it as disposable. Templates may read
  it with `command_output`, but it must not be committed back into repo-managed
  config.

If a refresh function fails, report the artifact and the command; do not leave a
half-written file that the next deploy will treat as source state.

## Helpers

Rhai helpers live in `.dotter/helpers/` and are registered under `[helpers]` in
`global.toml`. `url_userinfo_escape` escapes credentials embedded in a URL.

## Codex worktrees

Codex creates managed worktrees with
`git -c core.hooksPath=/dev/null worktree add --detach --no-checkout` followed
by `reset --hard`, so no Git hook observes the checkout. `codex/codex/hooks.json`
ships a `SessionStart` hook that runs
`codex/codex/scripts/jj-adopt-worktree.sh` and converts the worktree in place
with `jj git init --colocate`.

- `SessionStart` is the only Codex event that fires with the session cwd already
  set to the worktree; the TUI emits it lazily on the first message, so the hook
  runs before the agent's first tool call but not when the worktree is created.
- The script is a no-op everywhere else: it exits unless the cwd is a linked Git
  worktree (`gitdir != commondir`), the source repository has `.jj`, and the
  path is under `${CODEX_HOME:-$HOME/.config/codex}/worktrees`.
- A conversation that switches worktrees mid-session emits no event; that case
  stays manual.
- Adoption is a colocated jj repo inside the worktree, not a `jj workspace add`
  workspace. Codex removes the directory itself, so a separate workspace entry
  would be left stale.

## Session services

Graphical-session services are decoupled from the compositor through systemd
targets and drop-ins. Do not branch on `dotter.packages.<compositor>` in a unit.

### Session targets

- Services use `PartOf=` and `After=graphical-session.target`.
- Only a service that needs sway itself (`swayidle`, which calls `swaymsg`)
  belongs to `sway-session.target`; `sway` pulls it in with `Wants=` in the
  target.
- Sway owns the session target lifecycle:
  `sway/sway/config.d/50-autostart.conf` imports the compositor environment,
  starts `sway-session.target`, and `sway/sway/session-stop` stops it when sway
  exits.
- The login wrapper (`/etc/greetd/sway-run`, outside this repo) must not start
  the target, otherwise services start before `WAYLAND_DISPLAY` is imported.

### Service defaults

- A service that starts by default carries no `[Install]`. Its package ships
  `systemd/user/<target>.d/10-<unit>.conf` containing `[Unit] Wants=<unit>`, so
  selecting the package enables the service and removing it disables the
  service. Disable it on one machine with `systemctl --user mask`.
- A service that must stay opt-in keeps `[Install]` and ships no drop-in; enable
  it per machine with `systemctl --user enable`.
- A socket-activated service brings its daemon up through `default.target.d/`
  and its socket through `sockets.target.d/`.

### Extensions

Extensions point from the plugin to the host through the host's drop-in
directory: `sway/config.d/` for sway snippets (keybindings live with the package
that owns the tool) and `voxtype/output-hook.d/` for executables that voxtype
runs around typing, via `voxtype/output-hook pre|post`. The host never names its
plugins.
