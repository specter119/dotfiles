# Codex worktrees

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
