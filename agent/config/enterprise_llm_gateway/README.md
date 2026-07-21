# Enterprise LLM Gateway Models

`models.toml` is the shared, tracked source of enterprise model metadata.
Each top-level deployment table (`ali`, `azure`) owns one model list.

## Rendering pipeline

Pi and OpenCode do not load this catalog directly. During deployment, the
provider renderer (`render_gateway_providers.py`) reads `models.toml` together
with client credentials and deployment URLs from `.dotter/local.toml`, then
produces per-consumer provider configs via `pi/gateway-providers.json.j2` and
`opencode/gateway-providers.json.j2`.

## `.dotter/local.toml` configuration

The renderer combines every configured client with every catalog deployment.
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

Only `ali` and `azure` deployments are supported; the keys must match the catalog.
`base_url` values are machine-local and should not be committed.
