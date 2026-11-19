# Codex worktrees

Codex creates managed worktrees with
`git -c core.hooksPath=/dev/null worktree add --detach --no-checkout` followed
by `reset --hard`, so no Git hook observes the checkout. `codex/codex/hooks.json`
ships two `SessionStart` hooks and is mapped only while `jj` is selected, so no
hook can point at an absent script: `codex/codex/hooks/jj-adopt-worktree.sh`
converts the worktree in place with `jj git init --colocate`, and
`codex/codex/hooks/jj-sync-identity.sh` gives the resulting repo its jj identity
(see [jj identity](#jj-identity)).

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

## jj identity

jj reads `user.name` / `user.email` from its own config only: it ignores git's,
and its `--when` conditions match repository, workspace, hostname, command,
platform, and environment, never a remote URL. A jj commit in a checkout parked
outside the enterprise directories would therefore carry the default identity.

`codex/codex/hooks/jj-sync-identity.sh` closes that gap and is the second
`SessionStart` hook. It asks jj for the git backend (`jj git root`, which also
covers non-colocated repos), reads the identity git resolves for that remote,
and writes it with `jj config set --repo`. jj keeps repo-level config outside
the workspace, so one session per repository is enough and every workspace of
that repository inherits it.

- The identity itself still comes from git's `includeIf "hasconfig:remote.*.url:
  ..."`. The hook only copies the resolution; it never decides which identity a
  repository gets, so there is one rule for both tools.
- It is a no-op outside a jj repo, without a git backend, or when the repo-level
  config already agrees.
- Writing repo-level config overrides any hand-set `jj config set --repo
  user.email`. Use `--when` scopes in `jj/config.toml` for an exception.
- Adding or changing a `SessionStart` hook invalidates Codex's persisted hook
  trust: approve it once in the TUI, then re-run the reverse sync so
  `variables.codex.hook_states` records the new hash.
