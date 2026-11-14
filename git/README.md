# git config layout

Deployed to `~/.config/git`. `config` is the file git reads; every other file here is
pulled in by an `include` or `includeIf` directive inside it.

| File | Deployed as | Pulled in by | When |
|---|---|---|---|
| `config` | `config` | — (root) | always |
| `wsl.conf` | `platform.conf` | `[include]` in `config` | WSL only |
| `windows.conf` | `platform.conf` | `[include]` in `config` | Windows only |
| `enterprise.conf` | `enterprise.conf` | `includeIf` in `platform.conf` | `variables.git.enterprise` is non-empty |
| `github.conf` | `github.conf` | `includeIf` in `platform.conf` | repository under `scoop/` |
| `ignore` | `ignore` | `core.excludesfile` | always |
| `pkgbuild.gitignore` | `pkgbuild.gitignore` | `includeIf` in `config` | repository under `~/.cache/paru/clone` |

## Identity resolution

The default identity is inline in `config`. `platform.conf` overrides it per platform,
and the `includeIf` blocks override it again per directory. Git keeps the **last** value
for `user.name` and `user.email`, so the order below is what makes the override work:

1. inline `[user]` in `config` — default identity
2. `[include] platform.conf` — platform default
3. `includeIf` directory blocks — per-directory override

## Enterprise identity

Set the whole table in `.dotter/local.toml`. Leaving it out keeps the `{}` default from
`global.toml`, which deploys no `enterprise.conf` and emits no `includeIf` at all.

```toml
[variables.git.enterprise]
name = "..."
email = "..."
dirs_wsl = ["/mnt/c/Users/<you>/company/"]
dirs_windows = ["C:/Users/<you>/company/"]
```

Paths need a trailing slash: `gitdir` matches repositories *below* that directory.
`gitdir/i` is used on Windows because its filesystem is case-insensitive.

## Editing

These names are not `.gitconfig` or `.gitignore`, so each file starts with a Vim
modeline (`# vim: set ft=gitconfig:`) to keep editor highlighting correct.
