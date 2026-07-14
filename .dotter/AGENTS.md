# AGENTS.md

Scope: `.dotter/`

## Files Mapping Rules

- For files sharing the same prefix, write a single directory-level mapping instead of splitting into multiple exact file mappings.
  - ✅ `package = '~/.config/package'` (directory mapping — Dotter creates symlinks per file, including subdirectories)
  - ❌ Splitting into `package/config.toml` + `package/subdir/file.toml`
- Principle: write one line when possible; use multiple lines only when prefixes differ.

## Deploy Workflow

- Default to `dotter deploy` (without `--force`).
- When deploy reports "target contents were changed", inspect the diff first:
  1. If the difference is a value that varies per machine (model name, API key, path, etc.), extract it into a Dotter variable in `global.toml` / `local.toml` so the template absorbs the change.
  2. If the difference is a legitimate upstream change that should be committed, accept it into the repo template.
  3. Only use `--force` as a last resort after understanding the diff.
- Follow the repo-level reverse-sync decision framework before adding a variable. In particular, only Droid `trustedFolders` is templated and reverse-synced; manually reconcile all other Droid drift.

## Deployment Cache

- `.dotter/cache.toml` and `.dotter/cache/` are Dotter-owned state. Never edit or remove their entries manually.
- Add, modify, or remove source templates, then let a normal `dotter deploy` update cache state and clean obsolete targets.
- Use `dotter deploy --dry-run --verbose` to inspect the resulting target and cache operations before deploying.

## Deploy Scripts

- `.dotter/pre_deploy.sh` and `.dotter/post_deploy.sh` are for deploy-time glue that should not live in static templates. Keep these entry scripts POSIX `sh` compatible because Dotter may execute the rendered cache scripts through `/bin/sh`; call Bash-only helpers explicitly with `bash ...`.
- `.dotter/scripts/live_config_reverse_sync.py` is invoked from `.dotter/pre_deploy.sh` to reverse-sync tool-modified config values (e.g., trusted folders, default model) from live configs back into `local.toml`. See repo-level `AGENTS.md` for the decision framework and variable coverage.
- `.dotter/scripts/mcp_setup.sh` is only a manual backup for setting Claude MCP entries. It is not part of the normal deploy path.
- Keep `.dotter/scripts/mcp_setup.sh` scoped to Claude MCP only; do not add other agent setup there.
- Do not call `.dotter/scripts/mcp_setup.sh` from deploy hooks.
- Do not add post-deploy commands that write secrets or tool-generated runtime state back into repo-managed config files.
- These deploy scripts are also templates. Do not write a literal `{{` inside embedded shell or Python snippets; build it at runtime instead.

## Runtime Artifacts

- When multiple templates need the same deploy-time derived value, prefer writing a machine-local artifact under `$XDG_RUNTIME_DIR/dotter/` from `.dotter/pre_deploy.sh` instead of duplicating generation logic in each template.
- Treat files in `$XDG_RUNTIME_DIR/dotter/` as disposable runtime artifacts. Templates may read them with `command_output`, but they must not be committed back into repo-managed config.
- Current registry flow: `.dotter/pre_deploy.sh` writes `registry-auth-encode` from `registry-auth.user_id` and `registry-auth.access_token`, `npmrc/.npmrc` reads it for npm auth, and Bun inherits that auth through the deployed `~/.npmrc`.
