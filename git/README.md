# git config layout

Deployed to `~/.config/git`. `config` is the file git reads; every other file here is
pulled in by an `include` or `includeIf` directive inside it.

| File | Deployed as | Pulled in by | When |
|---|---|---|---|
| `config` | `config` | — (root) | always |
| `wsl.conf` | `platform.conf` | `[include]` in `config` | WSL only |
| `windows.conf` | `platform.conf` | `[include]` in `config` | Windows only |
| `enterprise.conf` | `enterprise.conf` | `includeIf hasconfig:remote.*.url` in `config` | `variables.git.enterprise` is non-empty |
| `ignore` | `ignore` | `core.excludesfile` | always |
| `pkgbuild.gitignore` | `pkgbuild.gitignore` | `includeIf` in `config` | repository under `~/.cache/paru/clone` |

## Identity resolution

The default identity (personal GitHub) is inline in `config` and is the only
unconditional one. Git keeps the **last** value for `user.name` and `user.email`,
so the order below is what makes an override work:

1. inline `[user]` in `config` — default identity
2. `[include] platform.conf` — platform `[core]` flags and credential helper, no identity
3. `includeIf` blocks — enterprise identity

The identity is selected by the repository's **remote URL**, not its path. A
clone, a `git worktree`, or an agent workspace parked anywhere resolves the same
identity as long as the remote matches, and `git config user.email` inside the
checkout reports it.

## Enterprise identity

Set the whole table in `.dotter/local.toml`. Leaving it out keeps the `{}` default from
`global.toml`, which deploys no `enterprise.conf` and emits no `includeIf` at all.

```toml
[variables.git.enterprise]
name = "..."
email = "..."
remotes = [
  "git@gitlab.example.com:*/**",
  "https://*gitlab.example.com/**",
]
```

`remotes` holds `hasconfig:remote.*.url` glob patterns, one `includeIf` per
entry. Git ≥ 2.36 scans the repository's remotes for these conditions, so an
older git silently ignores them and keeps the default identity.

Pattern rules, from `man git-config`:

- Only `*` (within one path component) and the two multi-component forms `**/`
  and `/**` are special. `gitlab.example.com:**`, `**gitlab.example.com**`, and
  `gitlab.example.com**` do not behave like a prefix match; the trailing `**`
  needs a `/` in front of it to span components.
- The pattern is matched against the **stored** URL. An `insteadOf` rewrite
  (`[url "ssh://git@ssh.github.com:443/"]` in `config`) does not change what the
  condition sees, so an scp-like remote needs its scp-like pattern.
- The match is case-sensitive: `https://GitHub.example.com/**` does not hit
  `https://github.example.com/**`.
- Every matching block applies in file order, so a repository with both a
  personal and an enterprise remote ends up with the **last** one listed.
- A file pulled in this way may not declare remotes; git treats that as a config
  cycle.

## Editing

`config` is a template: the `includeIf` list is emitted from
`variables.git.enterprise.remotes`. `git config --global ...` writes are
therefore written into the deployed copy and overwritten on the next deploy;
edit the source here instead.

These names are not `.gitconfig` or `.gitignore`, so each file starts with a Vim
modeline (`# vim: set ft=gitconfig:`) to keep editor highlighting correct.
