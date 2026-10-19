# AGENTS.md

Scope: `.dotter/`

## Files Mapping Rules

- For files sharing the same prefix, write a single directory-level mapping instead of splitting into multiple exact file mappings.
  - ✅ `package = '~/.config/package'` (directory mapping — Dotter creates symlinks per file, including subdirectories)
  - ❌ Splitting into `package/config.toml` + `package/subdir/file.toml`
- Principle: write one line when possible; use multiple lines only when prefixes differ.
- Prefer directory mappings and minimize entries in the global mapping table. Add another mapping only when the target root or mapping semantics differ; do not use exact-file mappings when one directory mapping can express the same relationship.

## Deploy Workflow

- Default to `dotter deploy` (without `--force`).
- When deploy reports "target contents were changed", inspect the diff first:
  1. Align with the user on the intended source of truth before changing either side. Do not overwrite live state, accept it into a template, or add a variable based on inference alone.
  1. If the user chooses a machine-specific value (model name, API key, path, etc.), extract it into a Dotter variable in `global.toml` / `local.toml` so the template absorbs the change.
  1. If the user chooses the live change as the shared source, accept it into the repo template.
  1. Only use `--force` as a last resort after the user has explicitly chosen the repo-managed value.
- Follow the repo-level reverse-sync decision framework before adding a variable. Apply this workflow to every Dotter-managed target, including reverse-synced values.

## Deployment Cache

- `.dotter/cache.toml` and `.dotter/cache/` are Dotter-owned state. Never edit or remove their entries manually.
- Add, modify, or remove source templates, then let a normal `dotter deploy` update cache state and clean obsolete targets.
- Use `dotter deploy --dry-run --verbose` to inspect the resulting target and cache operations before deploying.

## Deploy Scripts

- `.dotter/pre_deploy.sh` and `.dotter/post_deploy.sh` are for deploy-time glue that should not live in static templates. Keep these entry scripts POSIX `sh` compatible because Dotter may execute the rendered cache scripts through `/bin/sh`; call Bash-only helpers explicitly with `bash ...`.
- `.dotter/scripts/live_config_reverse_sync.py` is invoked from `.dotter/pre_deploy.sh` to reverse-sync tool-modified config values (e.g., Codex model and trusted projects, Droid trusted folders, Pi defaults) from live configs back into `local.toml`. See repo-level `AGENTS.md` for the decision framework and variable coverage.
- Do not add post-deploy commands that write secrets or tool-generated runtime state back into repo-managed config files.
- These deploy scripts are also templates. Do not write a literal `{{` inside embedded shell or Python snippets; build it at runtime instead.
- `post_deploy.sh` identifies templates with comment-wrapped Handlebars controls by content, not filename extension, before removing residual blank `#` lines from their target and cache copies.

## Runtime Artifacts

- `post_deploy.sh` `refresh_magpie_codex_catalog` regenerates `~/.config/codex/magpie-models.json` by fetching `/backend-api/codex/models?client_version=<codex version>` from the magpie gateway, using the base URL and bearer token of `model_providers.magpie` in the deployed `config.toml`. This route returns the catalog in Codex's own format. Do not run `magpie codex <model>` for this: it rewrites `config.toml` (which Dotter owns, so the next deploy refuses it) and records state in `stash.json`. The step is skipped unless `config.toml` references `magpie-models.json`, and a failed fetch keeps the previous file.

- `post_deploy.sh` `refresh_magpie_pi_models` runs `magpie pi <pi.default_model>` with the value from `.dotter/local.toml`, only when `pi.default_provider` is `magpie`, to refresh the live `~/.config/pi/models.json`. The argument equals what Dotter just rendered into `pi/settings.json`, so magpie leaves `settings.json` content unchanged and the next deploy sees no target change. If the model differs from the rendered one, magpie would rewrite `settings.json` and trigger a "target contents were changed" error. A failure only warns.

- Runtime artifacts are deploy-time files. When multiple templates need the same derived value, prefer writing a machine-local artifact under `$XDG_RUNTIME_DIR/dotter/` from `.dotter/pre_deploy.sh` instead of duplicating generation logic in each template.

- Treat files in `$XDG_RUNTIME_DIR/dotter/` as disposable runtime artifacts. Templates may read them with `command_output`, but they must not be committed back into repo-managed config.

- Registry credentials are owned by the `enterprise-artifact` package (see `Package Organization` in the root `AGENTS.md`). `.dotter/pre_deploy.sh` does not depend on its variables.
