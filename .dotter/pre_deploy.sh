#!/bin/sh

# Sync current agent default models into local.toml before templates render.
uv run .dotter/scripts/live_config_reverse_sync.py

# Refresh Bitwarden vault data before any template or post-deploy script reads it.
rbw sync
