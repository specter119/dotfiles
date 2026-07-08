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
  printf '%s:%s' "{{registry-auth.user_id}}" "{{registry-auth.access_token}}" \
    | base64 | tr -d '\n' > /tmp/dotter-docker-auth-base64
fi
