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
- Reasoning levels follow [models.dev](https://models.dev) (`api.json`,
  `reasoning_options`). Do not widen them from assumptions: the gateway
  rejects unsupported values with HTTP 400.
  - `effort` values become the `reasoning` array; `none` is written as `off`.
  - A `toggle` option adds `off`; with no `effort` option, use `reasoning = true`.
  - No `none`/toggle option means no `off` level (e.g. `gpt-6-astra`).
  - `minimal` is never listed; the gateway rejects it for every GPT model.
  - Prefer the entry for the same model on the matching provider (Alibaba
    entries for `ali`, OpenAI entries for `azure`).
- The azure GPT levels were re-probed against the gateway and match
  models.dev exactly: `gpt-5.1-codex-mini` accepts `low|medium|high`;
  `gpt-5.4-mini` and `gpt-5.5` accept `none|low|medium|high|xhigh` (no `max`);
  `gpt-5.6-*`, `gpt-6-luna` and `gpt-6-sol` accept `none` through `max`;
  `gpt-6-astra` and `gpt-6.1-sol` accept `low` through `max` (no `none`).
- Context/output limits are the exception: the catalog keeps conservative
  per-model values (for example `glm-5.2` and `glm-5.3` use 367232/32768),
  not the models.dev maxima.
- `deepseek-v4-flash` (azure) also answers the Responses API but rejects
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
