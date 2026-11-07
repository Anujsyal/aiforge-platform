#!/usr/bin/env bash
# Vault pod restart (ya node reboot) ke baad Vault SEALED hota hai → ESO secrets sync nahi karta.
set -euo pipefail
INIT_FILE="${INIT_FILE:-vault-init.json}"
KEY=$(python -c "import json;print(json.load(open('$INIT_FILE'))['unseal_keys_b64'][0])")
kubectl -n vault exec vault-0 -- vault operator unseal "$KEY"
