# dotfiles

Cross-platform dotfiles managed by [dotter](https://github.com/SuperCuber/dotter).

## Git enterprise identities

Add enterprise Git identities in `.dotter/local.toml` under `variables.git_enterprise`.
The intermediate empty table does not need to be declared explicitly.

```toml
[variables.git_enterprise.company_a]
repo_dir = "~/Documents/company-a.repos/"
name = "your-work-name"
email = "your-work-email@company-a.example"

[variables.git_enterprise.company_b]
repo_dir = "~/Documents/company-b.repos/"
name = "your-other-work-name"
email = "your-other-work-email@company-b.example"
```

Each entry generates `git/generated/<key>.conf`, then Dotter links it to `~/.config/git/generated/<key>.conf`.
