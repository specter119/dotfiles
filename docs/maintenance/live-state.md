# Live state and reverse sync

A template and a tool that rewrites the same file are two writers. Dotter sees a
changed target and refuses to deploy; a force deploy loses the tool's change.

## When to reverse sync

A value needs reverse sync when the tool modifies it and deploy would lose it:

1. **Machine-specific config** — the same setting differs across machines; the
   user switches it in the tool UI.
2. **Tool-side-effect state** — trusted folders, dismissed banners, and similar
   values the user does not treat as config.
3. **Time-sensitive markers** — version numbers, read receipts, changelog
   versions.
4. **Temporary workaround** — a model switch because a quota is exhausted.

A value does **not** need reverse sync when the user maintains it deliberately:
API keys, manually selected models, and plugin lists in `local.toml`, or static
content hardcoded in the template.

`pre_deploy.sh` runs `.dotter/scripts/live_config_reverse_sync.py` before
templates render. The script normalizes, compares, and writes only changed
values into `local.toml`.

Do not let a reverse-sync path write a machine-specific value into a tracked
file; the value belongs in `local.toml`.

## Match the tool's serialization

A tidy template drifts as soon as its bytes differ from the tool's writer.
Reproduce the tool's serializer:

- key order, indentation, and whether a key exists at all;
- an `omitempty` field renders as no key, not as `{}`;
- Go's `encoding/json` sorts map keys and writes a non-empty map multi-line, so
  a one-line `{ ... }` never matches;
- gate a collection key with `{{#if}}` so empty and non-empty renders both
  match, and keep the control inline (`{ {{~#each ...}}`; `{{{` parses as a
  triple-stash) so the bytes match;
- reverse-sync the values the tool writes back into `local.toml`;
- keys the tool derives belong in neither the template nor `local.toml`;
  rendering a copy makes every deploy skip.

`magpie/settings.json` pins `guideHidden` and `textSize` because magpie always
writes them, renders `modelWires` only when non-empty because magpie omits an
empty map, and leaves `modelCompacts` out because magpie derives it.

## Local schema differences

When a variable is renamed or removed, update the tracked placeholder, template,
and documentation to the new schema. Do not silently migrate, copy, or delete a
legacy key in `local.toml`.

If a local schema still contains a legacy key, surface the difference and ask
the user whether to keep, migrate, or remove it. Deploy and reverse-sync scripts
must never make that choice automatically.

## Implementation

1. Declare the variable in `.dotter/global.toml` with its namespace and default.
2. Reference it in the template with `#each` / `#if`.
3. Add a normalize-compare-write `sync_*` function in
   `.dotter/scripts/live_config_reverse_sync.py`.
4. Register the call in `main()` in the corresponding agent block.
5. Run a dry-run deploy and confirm the render matches the live file.

Dotter loads `local.toml` before running the hook, so a value that changed since
the last deploy is not visible to the current render. The first deploy reports
`target contents were changed` and skips that file; the next deploy converges.
To converge in one pass, run
`uv run .dotter/scripts/live_config_reverse_sync.py && dotter deploy`.

Checks and evidence live in
`.agents/skills/dotfiles-live-state-review/SKILL.md`.

## Deploy conflict

A conflict means the live file changed. Extract the value into a variable or
accept the live value; do not reach for `--force` first. See
`deploy.md#deploy-workflow`.
