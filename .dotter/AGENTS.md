# AGENTS.md

Scope: `.dotter/`

## Files Mapping Rules

- A mapping pairs a source root with a target root; Dotter links every file under it individually, so a mapping never owns a directory as a unit.
- Give each target root one mapping and minimize entries in the global mapping table. Do not split a shared prefix into exact-file mappings, and add another mapping only when the target root or the mapping semantics differ.
  - ✅ `package = '~/.config/package'` (one mapping; Dotter creates a symlink per file, including subdirectories)
  - ❌ `package/config.toml` + `package/subdir/file.toml`
- Because links are per file, retiring one file means deleting the source file and deploying once; until Dotter drops the stale symlink, the tool writes through it back into the repository.

## Deploy Workflow

- Default to `dotter deploy` (without `--force`).
- When deploy reports "target contents were changed", inspect the diff first:
  1. Align with the user on the intended source of truth before changing either side. Do not overwrite live state, accept it into a template, or add a variable based on inference alone.
  1. If the user chooses a machine-specific value (model name, API key, path, etc.), extract it into a Dotter variable in `global.toml` / `local.toml` so the template absorbs the change.
  1. If the user chooses the live change as the shared source, accept it into the repo template.
  1. Only use `--force` as a last resort after the user has explicitly chosen the repo-managed value.
- Follow the repo-level reverse-sync decision framework before adding a variable. Apply this workflow to every Dotter-managed target, including reverse-synced values.

## Rhai Helpers

- Custom helpers are registered under `[helpers]` in `global.toml` and live in `.dotter/helpers/*.rhai`.
- Use `url_userinfo_escape` for any URL a Go `net/url` consumer parses (magpie `proxy`); the helper's header explains why.

## Deployment Cache

- `.dotter/cache.toml` and `.dotter/cache/` are Dotter-owned state: never edit their entries manually, and let a normal `dotter deploy` update them and drop obsolete targets after you add, modify, or remove source templates.
- Use `dotter deploy --dry-run --verbose` to inspect the resulting target and cache operations before deploying.

## Deploy Scripts

- `.dotter/pre_deploy.sh` and `.dotter/post_deploy.sh` are for deploy-time glue that should not live in static templates. Keep these entry scripts POSIX `sh` compatible because Dotter may execute the rendered cache scripts through `/bin/sh`; call Bash-only helpers explicitly with `bash ...`.
- `.dotter/scripts/live_config_reverse_sync.py` runs from `pre_deploy.sh` and writes tool-modified live values back into `local.toml` before templates render.
- `republish_magpie_settings` renames the rendered `magpie/settings.json` into place: magpie reads that file while it runs and must never see a truncated one.
- Do not add post-deploy commands that write secrets or tool-generated runtime state back into repo-managed config files.
- Do not post-process rendered targets to strip template residue. Standalone control blocks stay on bare lines so Dotter drops them ([root `AGENTS.md`, Template Patterns](../AGENTS.md#template-patterns)); a `# `-prefixed control renders as a `# ` line, and deleting that line after deploy makes every later deploy see a diff.
- These deploy scripts are also templates. Do not write a literal `{{` inside embedded shell or Python snippets; build it at runtime instead.
- Registry credentials are owned by the `enterprise-artifact` package (see `Package Organization` in the root `AGENTS.md`); `pre_deploy.sh` does not depend on its variables.

## Runtime Artifacts

- `refresh_magpie_codex_catalog` writes `~/.config/codex/magpie-models.json` from the gateway, not from `magpie codex`: that command rewrites the Dotter-owned `config.toml`.

- `refresh_magpie_pi_models` runs `magpie pi` with the model Dotter just rendered, so magpie leaves `pi/settings.json` byte-equal; any other model makes it rewrite the file and the next deploy refuses it. The responses normalization must follow every `magpie pi` run, because magpie rewrites `models.json` each time.

- `refresh_magpie_dsh_models` runs `magpie dsh` with `dsh.default_model`, then puts the provider back on the Anthropic wire: magpie owns the model list, the wire is ours.

- The refresh steps warn and keep the previous artifact when they fail. Route, format and normalization details live in the script comments, not here.

- Runtime artifacts are deploy-time files under `$XDG_RUNTIME_DIR/dotter/`: prefer writing one there from `.dotter/pre_deploy.sh` when several templates need the same derived value, and treat it as disposable. Templates may read it with `command_output`, but it must not be committed back into repo-managed config.
