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
  1. Align with the user on the intended source of truth before changing either side. Do not overwrite live state, accept it into a template, or add a variable based on inference alone.
  2. If the user chooses a machine-specific value (model name, API key, path, etc.), extract it into a Dotter variable in `global.toml` / `local.toml` so the template absorbs the change.
  3. If the user chooses the live change as the shared source, accept it into the repo template.
  4. Only use `--force` as a last resort after the user has explicitly chosen the repo-managed value.
- Follow the repo-level reverse-sync decision framework before adding a variable. Apply this workflow to every Dotter-managed target, including reverse-synced values.

## Deployment Cache

- `.dotter/cache.toml` and `.dotter/cache/` are Dotter-owned state. Never edit or remove their entries manually.
- Add, modify, or remove source templates, then let a normal `dotter deploy` update cache state and clean obsolete targets.
- Use `dotter deploy --dry-run --verbose` to inspect the resulting target and cache operations before deploying.

## Deploy Scripts

- `.dotter/pre_deploy.sh` and `.dotter/post_deploy.sh` are for deploy-time glue that should not live in static templates. Keep these entry scripts POSIX `sh` compatible because Dotter may execute the rendered cache scripts through `/bin/sh`; call Bash-only helpers explicitly with `bash ...`.
- `.dotter/scripts/live_config_reverse_sync.py` is invoked from `.dotter/pre_deploy.sh` to reverse-sync tool-modified config values (e.g., Codex trusted projects and model provider, Droid trusted folders, Pi defaults) from live configs back into `local.toml`. See repo-level `AGENTS.md` for the decision framework and variable coverage.
- `.dotter/scripts/mcp_setup.sh` is only a manual backup for setting Claude MCP entries. It is not part of the normal deploy path.
- Keep `.dotter/scripts/mcp_setup.sh` scoped to Claude MCP only; do not add other agent setup there.
- Do not call `.dotter/scripts/mcp_setup.sh` from deploy hooks.
- Do not add post-deploy commands that write secrets or tool-generated runtime state back into repo-managed config files.
- These deploy scripts are also templates. Do not write a literal `{{` inside embedded shell or Python snippets; build it at runtime instead.
- `post_deploy.sh` identifies templates with comment-wrapped Handlebars controls by content, not filename extension, before removing residual blank `#` lines from their target and cache copies.

## Enterprise Provider Rendering

Enterprise provider data is rendered inline rather than written as a runtime artifact:

```text
.dotter/local.toml
  [[variables.agent.enterprise_clients]] × [variables.agent.enterprise_deployments]
                                     +
agent/config/enterprise_llm_gateway/models.toml
    ↓
.dotter/scripts/render_gateway_providers.py
    ├── pi/gateway-providers.json.j2
    └── opencode/gateway-providers.json.j2
    ↓
command_output in pi/models.json or opencode/config/opencode.jsonc
```

- `models.toml` is the shared model source and is deployed to `~/.config/enterprise_llm_gateway/`; Pi and OpenCode do not load it directly.
- Update model metadata in `models.toml`; machine-specific client credentials and deployment URLs in `.dotter/local.toml`; consumer JSON shape in the adjacent Jinja adapter; and shared validation or consumer registration in `render_gateway_providers.py`.
- The Python script loads `models.toml` and `.dotter/local.toml`, requires matching deployment names, validates their strict schemas, selects the consumer template, and validates its JSON stdout. Keep consumer schema conversion in the adjacent Jinja template.
- Jinja templates use `[% ... %]` and `[[ ... ]]` delimiters, not `{{ ... }}`, so Dotter does not parse their source as Handlebars.
- Jinja templates are build inputs, not live configuration. The explicit `pi.files` mappings intentionally exclude `pi/gateway-providers.json.j2`; preserve that exclusion when changing Pi mappings.
- The renderer passes deployment names through unchanged. Consumer adapters assign their semantics: OpenCode uses `@ai-sdk/openai` and `-sdlc-gs` model names for `azure`, and `@ai-sdk/openai-compatible` otherwise; Pi applies the Azure `-sdlc-gs` per-model URL transform.
- Validate before deployment:
  ```sh
  uv run .dotter/scripts/render_gateway_providers.py pi | jq empty
  uv run .dotter/scripts/render_gateway_providers.py opencode | jq empty
  ```

## Runtime Artifacts

- Runtime artifacts are deploy-time files, distinct from the inline enterprise provider rendering above. When multiple templates need the same derived value, prefer writing a machine-local artifact under `$XDG_RUNTIME_DIR/dotter/` from `.dotter/pre_deploy.sh` instead of duplicating generation logic in each template.
- Treat files in `$XDG_RUNTIME_DIR/dotter/` as disposable runtime artifacts. Templates may read them with `command_output`, but they must not be committed back into repo-managed config.
- Current registry flow: `.dotter/pre_deploy.sh` writes `registry-auth-encode` from `registry-auth.user_id` and `registry-auth.access_token`, `npmrc/.npmrc` reads it for npm auth, and Bun inherits that auth through the deployed `~/.npmrc`.
