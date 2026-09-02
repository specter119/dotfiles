# Enterprise LLM Gateway Models

`models.toml` is the shared, tracked source of enterprise model metadata.
Each top-level deployment table (`ali`, `azure`) owns one model list.

## Protocol routing

- `azure` models run the **OpenAI Responses API**: `{azure.base_url}/responses`
  (base_url is `…/v2/openai/v1`; the consumer templates append the `-sdlc-gs`
  deployment suffix to the request model name).
- `ali` models run **Chat Completions**: `{ali.base_url}/chat/completions`
  with a bare model id. The gateway exposes no responses route for ali
  deployments.
- gpt-5.x `reasoning.effort` accepts `none|low|medium|high|xhigh|max`;
  `minimal` is rejected, so `reasoning` arrays exclude it.
- `deepseek-v4-flash` (azure) also answers the responses endpoint but rejects
  the `reasoning.effort` parameter entirely, hence `reasoning = false` in the
  catalog. Its bare id collides with the disabled ali snapshot of the same
  name (see `models.toml`).

## Rendering pipeline

Consumers do not load this catalog directly. During deployment, the provider
renderer (`render_gateway_providers.py`) reads `models.toml` together with
client credentials and deployment URLs from `.dotter/local.toml`, then
produces per-consumer provider configs:

- `pi/gateway-providers.json.j2`, `opencode/gateway-providers.json.j2` —
  provider definitions for Pi and OpenCode
- `codex-catalog` — the Codex `model_catalog_json` file (azure gpt models,
  request slugs carry the `-sdlc-gs` deployment suffix, metadata in the Codex
  catalog shape)

Deployment keys must exactly match a top-level table in `models.toml`.

### Clients (`agent.enterprise_clients`)

Array of tables — each entry provides one client identity:

```toml
[[variables.agent.enterprise_clients]]
client_id = "<client_name>"
api_key = "<api_key>"
```

### Deployments (`agent.enterprise_deployments`)

Table of tables — each entry provides one deployment endpoint:

```toml
[variables.agent.enterprise_deployments.ali]
base_url = "…"

[variables.agent.enterprise_deployments.azure]
base_url = "…"
```

Only `ali` and `azure` deployments are supported.
`base_url` values are machine-local and should not be committed.
