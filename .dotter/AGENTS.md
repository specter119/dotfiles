# AGENTS.md

Scope: `.dotter/`

- `.dotter/pre_deploy.sh` and `.dotter/post_deploy.sh` are for deploy-time glue that should not live in static templates.
- In `.dotter/scripts/mcp_setup.sh`, only manage MCP via CLI for `claude` and `codex`.
- Do not add post-deploy commands that write secrets or tool-generated runtime state back into repo-managed config files.
- These deploy scripts are also templates. Do not write a literal `{{` inside embedded shell or Python snippets; build it at runtime instead.
