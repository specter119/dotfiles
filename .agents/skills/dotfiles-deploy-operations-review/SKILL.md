---
name: dotfiles-deploy-operations-review
description: >-
  Use when reviewing pre_deploy, post_deploy, a deploy helper, the deploy
  cache, or a runtime artifact. Do not use for session targets, reverse-sync
  logic, or package mappings.
---

# Deploy scripts, cache, and artifacts review

## Scope

`pre_deploy.sh`, `post_deploy.sh`, deploy helpers, the deploy cache, and
runtime artifacts.

## Checks

- `pre_deploy.sh` runs reverse sync before templates render; a sync failure
  blocks the deploy.
- Scripts are POSIX sh, contain no literal `{{` in embedded code, and quote
  path expansions.
- A deploy conflict stops and surfaces the file. `--force` is not the default
  remedy.
- Cache and runtime artifacts stay under the documented paths. A generated leaf
  is not deleted unless a pre-deploy generator exists.
- A post-deploy patch is idempotent and does not rewrite an unrelated file.
- A failed deploy exits non-zero, leaves the previous live file in place, and
  prints the file that conflicted.
- A Codex `SessionStart` hook exits before touching anything it does not own.
  The adoption hook stays a no-op unless the cwd is a linked Git worktree under
  `${CODEX_HOME:-$HOME/.config/codex}/worktrees` and the source repo has `.jj`;
  the identity hook stays a no-op unless the cwd is a jj repo with a git
  backend and the repo-level identity disagrees with git's.

## Required evidence

The script, the deploy log or exit code, the cache path, and the conflict
message.

## Owner documents

- `docs/maintenance/deploy.md#deploy-workflow`
- `docs/maintenance/deploy.md#scripts`
- `docs/maintenance/deploy.md#runtime-artifacts`
- `docs/maintenance/deploy.md#helpers`

## Does not own

- Session targets and units: `dotfiles-service-lifecycle-review`
- Reverse-sync logic: `dotfiles-live-state-review`
- Package selection and mappings: `dotfiles-config-composition-review`
