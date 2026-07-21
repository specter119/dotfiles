# Enterprise LLM Gateway Models

`models.toml` is the shared source of enterprise model metadata. Dotter deploys
it to `~/.config/enterprise_llm_gateway/models.toml`.

Each top-level deployment table owns one model list. Keep machine-local
deployment URLs and client credentials in `.dotter/local.toml`.

Pi and OpenCode do not load this catalog directly. The provider renderer reads
it during deployment, while provider-specific conversions remain in
`pi/gateway-providers.json.j2` and `opencode/gateway-providers.json.j2`.
