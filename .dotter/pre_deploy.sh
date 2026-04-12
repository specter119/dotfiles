#!/bin/sh

# Refresh Bitwarden vault data before any template or post-deploy script reads it.
rbw sync
