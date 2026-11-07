#!/usr/bin/env bash
# Vault EK BAAR initialize + unseal + ESO ke liye configure.
#  - Lab: 1 key share / threshold 1 (production: 5 shares / 3 threshold, ya AWS KMS auto-unseal)
#  - vault-init.json (unseal key + root token) .gitignore mein hai. Password manager mein rakh, chat/screenshot mein NAHI.
set -euo pipefail
NS=vault
POD=vault-0
INIT_FILE="${INIT_FILE:-vault-init.json}"
vexec() { kubectl -n "$NS" exec -i "$POD" -- env VAULT_TOKEN="${ROOT_TOKEN:-}" vault "$@"; }

if kubectl -n "$NS" exec "$POD" -- vault status -format=json 2>/dev/null | grep -q '"initialized": true'; then
  echo "Vault already initialized."
else
  echo "Initializing Vault..."
  kubectl -n "$NS" exec "$POD" -- vault operator init -key-shares=1 -key-threshold=1 -format=json > "$INIT_FILE"
  echo "Saved $INIT_FILE  (ISKO SAFE RAKH)"
fi

UNSEAL_KEY=$(python -c "import json;print(json.load(open('$INIT_FILE'))['unseal_keys_b64'][0])")
ROOT_TOKEN=$(python -c "import json;print(json.load(open('$INIT_FILE'))['root_token'])")
export ROOT_TOKEN

kubectl -n "$NS" exec "$POD" -- vault operator unseal "$UNSEAL_KEY" >/dev/null && echo "Unsealed."

# KV v2 at secret/
vexec secrets list -format=json | grep -q '"secret/"' || vexec secrets enable -path=secret kv-v2

# Kubernetes auth: ESO apne ServiceAccount token se login karega; Vault us token ko TokenReview API se verify karta hai
vexec auth list -format=json | grep -q '"kubernetes/"' || vexec auth enable kubernetes
vexec write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc:443"

# Read-only policy: ESO sirf padh sakta hai (likh nahi sakta)
kubectl -n "$NS" exec -i "$POD" -- env VAULT_TOKEN="$ROOT_TOKEN" vault policy write external-secrets-read - <<'EOF'
path "secret/data/platform/*" { capabilities = ["read"] }
path "secret/data/teams/*"    { capabilities = ["read"] }
path "secret/metadata/*"      { capabilities = ["read", "list"] }
EOF

vexec write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets-read ttl=1h

echo "Done. Ab: ./scripts/vault-seed-secrets.sh"
