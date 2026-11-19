#!/bin/sh
# Seed this repository's jj identity from the identity git resolves for it.
#
# jj never reads git's user.name or user.email, and its conditional config can
# only match a repository path, so a jj commit in a checkout parked anywhere
# (Codex worktrees, an agent workspace) would be authored with jj's default
# identity. git resolves the right one on its own: the enterprise includeIf in
# ~/.config/git/config matches the repository's remote URL. This hook copies
# that resolution into the repository's jj config, which jj persists outside the
# workspace, so one session is enough.
#
# Codex runs this as a SessionStart hook. Every other start is a no-op: not a jj
# repo, no git backend, or an identity that already agrees.
set -eu

payload=$(cat 2>/dev/null || true)
cwd=$(printf '%s' "$payload" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("cwd", ""))' 2>/dev/null || true)
[ -n "$cwd" ] || cwd=$PWD

[ -d "$cwd/.jj" ] || exit 0

# Non-colocated repos keep the git backend under .jj, so ask jj for the git dir
# instead of assuming a .git in the workspace.
gitdir=$(jj -R "$cwd" git root 2>/dev/null) || exit 0

name=$(git --git-dir="$gitdir" config --get user.name 2>/dev/null) || exit 0
email=$(git --git-dir="$gitdir" config --get user.email 2>/dev/null) || exit 0
[ -n "$name" ] && [ -n "$email" ] || exit 0

current_name=$(jj -R "$cwd" config get user.name 2>/dev/null || true)
current_email=$(jj -R "$cwd" config get user.email 2>/dev/null || true)
[ "$current_name" = "$name" ] && [ "$current_email" = "$email" ] && exit 0

jj -R "$cwd" config set --repo user.name "$name" >/dev/null 2>&1 || exit 0
jj -R "$cwd" config set --repo user.email "$email" >/dev/null 2>&1 || exit 0
exit 0
