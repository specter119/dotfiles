#!/bin/sh

# Sync current agent default models into local.toml before templates render.
uv run .dotter/scripts/live_config_reverse_sync.py

# Refresh Bitwarden vault data before any template or post-deploy script reads it.
rbw sync

# Compute Docker registry auth base64 from registry-auth variables.
# Note: Handlebars #each + command_output + replace + variable refs have a bug,
# so we pre-compute the value here (pre_deploy is also a template).
# The docker/config.json template reads this file via command_output.
if [ -n "{{registry-auth.user_id}}" ] && [ -n "{{registry-auth.access_token}}" ]; then
  mkdir -p "$XDG_RUNTIME_DIR/dotter"
  printf '%s:%s' "{{registry-auth.user_id}}" "{{registry-auth.access_token}}" \
    | base64 | tr -d '\n' > "$XDG_RUNTIME_DIR/dotter/registry-auth-encode"
fi

# Render enterprise model providers before Dotter processes config templates.
# A command_output helper cannot consume a nested #each value.
runtime_dir="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR must be set}/dotter"
mkdir -p "$runtime_dir"
pi_entries=$(mktemp "$runtime_dir/pi-model-providers.XXXXXX")
opencode_entries=$(mktemp "$runtime_dir/opencode-providers.XXXXXX")
trap 'rm -f "$pi_entries" "$opencode_entries"' EXIT HUP INT TERM

printf '%s\n' '{}' > "$pi_entries"
printf '%s\n' '{}' > "$opencode_entries"

# {{#each agent.enterprise_clients as |client_value client_key|}}
# {{#each @root.agent.enterprise_deployments as |deploy_value deploy_key|}}
jq -cn \
  --arg key "{{client_key}}|{{deploy_key}}" \
  --arg api_key "{{client_value.api_key}}" \
  --arg base_url "{{deploy_value.base_url}}" \
  --slurpfile models "pi/{{deploy_value.models_file}}" \
  '{
    ($key): {
      api: "openai-completions",
      apiKey: $api_key,
      baseUrl: $base_url,
      compat: {
        maxTokensField: "max_tokens",
        supportsDeveloperRole: false
      },
      models: $models[0]
    }
  }' >> "$pi_entries"

jq -cn \
  --arg key "{{client_key}}|{{deploy_key}}" \
  --arg api_key "{{client_value.api_key}}" \
  --arg base_url "{{deploy_value.base_url}}" \
  --arg npm "{{#if deploy_value.npm}}{{deploy_value.npm}}{{else}}@ai-sdk/openai-compatible{{/if}}" \
  --slurpfile models "opencode/{{deploy_value.models_file}}" \
  '{
    ($key): {
      npm: $npm,
      name: $key,
      options: {
        baseURL: $base_url,
        apiKey: $api_key,
        useDeploymentBasedUrls: true,
        setCacheKey: true
      },
      models: $models[0]
    }
  }' >> "$opencode_entries"
# {{/each}}
# {{/each}}

jq -s 'add' "$pi_entries" > "$runtime_dir/pi-model-providers.json"
jq -s 'add' "$opencode_entries" > "$runtime_dir/opencode-model-providers.json"
