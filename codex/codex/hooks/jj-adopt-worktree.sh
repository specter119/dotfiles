#!/bin/sh
# Adopt a Codex-managed Git worktree as a colocated jj repo.
#
# Codex creates its worktrees with `git -c core.hooksPath=/dev/null worktree
# add --detach --no-checkout` plus a `reset --hard`, so no Git hook can observe
# the checkout. `SessionStart` is the only lifecycle Codex exposes, and it runs
# with the session cwd already set to the new worktree.
#
# The guard below keeps every other startup a no-op: plain sessions in the
# source repository, worktrees of non-jj repositories, and directories outside
# the Codex worktree root.
set -eu

payload=$(cat 2>/dev/null || true)
cwd=$(printf '%s' "$payload" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("cwd", ""))' 2>/dev/null || true)
[ -n "$cwd" ] || cwd=$PWD

# Already a jj repo (source repo, or a worktree adopted on an earlier start).
[ -d "$cwd/.jj" ] && exit 0

gitdir=$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0

# A linked worktree resolves its git dir under the common dir; the source
# checkout resolves both to the same path.
[ "$gitdir" != "$common" ] || exit 0

# Only adopt when the source repository is itself a jj repo.
main=${common%/.git}
[ -d "$main/.jj" ] || exit 0

root=${CODEX_WORKTREE_ROOT:-${CODEX_HOME:-$HOME/.config/codex}/worktrees}
case "$cwd" in
  "$root"/*) ;;
  *) exit 0 ;;
esac

cd "$cwd"
jj git init --colocate >/dev/null 2>&1 || exit 0
exit 0
