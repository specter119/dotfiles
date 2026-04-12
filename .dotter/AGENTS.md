# AGENTS.md

Scope: `.dotter/`

## Files Mapping Rules

- For files sharing the same prefix, write a single directory-level mapping instead of splitting into multiple exact file mappings.
  - ✅ `package = '~/.config/package'` (directory mapping — Dotter creates symlinks per file, including subdirectories)
  - ❌ Splitting into `package/config.toml` + `package/subdir/file.toml`
- Principle: write one line when possible; use multiple lines only when prefixes differ.

## Deploy Scripts

- `.dotter/pre_deploy.sh` and `.dotter/post_deploy.sh` are for deploy-time glue that should not live in static templates. Keep these entry scripts POSIX `sh` compatible because Dotter may execute the rendered cache scripts through `/bin/sh`; call Bash-only helpers explicitly with `bash ...`.
- In `.dotter/scripts/mcp_setup.sh`, only manage MCP via CLI for `claude` and `codex`.
- Do not add post-deploy commands that write secrets or tool-generated runtime state back into repo-managed config files.
- These deploy scripts are also templates. Do not write a literal `{{` inside embedded shell or Python snippets; build it at runtime instead.
