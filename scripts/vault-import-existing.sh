#!/usr/bin/env bash
# Phase 4 ke MANUAL Kubernetes Secrets ko Vault mein import karo (same values), taaki ESO wahi Secret dobara banaye.
#
# Kyun import, naya generate nahi:
#   - LiteLLM DB ki teams/keys LITELLM_SALT_KEY se encrypted hain. Naya salt = purani keys bekaar = DB reset + re-onboard.
#   - Team ki virtual key + ingest token same rahe → app ko pata bhi nahi chalta (zero downtime).
#   Asli migration aise hi hoti hai: pehle existing secrets source-of-truth (Vault) mein, phir delivery (ESO) switch.
#
# Values kabhi screen pe print nahi hoti: kubectl → python (stdin) → vault kv put (stdin JSON).
# Idempotent: jo Vault path pehle se hai, skip (FORCE=1 se overwrite).
#
# Usage: ./scripts/vault-import-existing.sh [team=team-alpha] [app=team-alpha-rag]
set -euo pipefail
TEAM="${1:-team-alpha}" ; APP="${2:-team-alpha-rag}"
FORCE="${FORCE:-0}"
INIT_FILE="${INIT_FILE:-vault-init.json}"
ROOT_TOKEN=$(python -c "import json;print(json.load(open('$INIT_FILE'))['root_token'])")

vexists() { kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get -mount=secret "$1" >/dev/null 2>&1; }
# stdin JSON → `vault kv put path -` (values na command line pe, na screen pe)
vput_json() { kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv put -mount=secret "$1" - >/dev/null; echo "  wrote secret/$1"; }

# Kubernetes Secret ke chune hue keys → JSON (decoded). Arg: ns secret "vaultkey=secretkey ..."
secret_json() {
  kubectl -n "$1" get secret "$2" -o json | python -c "
import sys, json, base64
data = json.load(sys.stdin)['data']
out = {}
for pair in sys.argv[1].split():
    vk, sk = pair.split('=')
    if sk not in data: sys.exit(f'missing key {sk} in secret')
    out[vk] = base64.b64decode(data[sk]).decode()
print(json.dumps(out))" "$3"
}

import_secret() {  # vault_path ns secret mapping
  local path="$1" ns="$2" sec="$3" map="$4"
  if [[ "$FORCE" != "1" ]] && vexists "$path"; then echo "  skip secret/$path (exists)"; return; fi
  if ! kubectl -n "$ns" get secret "$sec" >/dev/null 2>&1; then echo "  skip secret/$path ($ns/$sec nahi mila)"; return; fi
  secret_json "$ns" "$sec" "$map" | vput_json "$path"
}

echo "== LiteLLM (ai-gateway/litellm-secrets) =="
import_secret platform/litellm ai-gateway litellm-secrets \
  "master_key=LITELLM_MASTER_KEY salt_key=LITELLM_SALT_KEY postgres_password=POSTGRES_PASSWORD"
import_secret platform/langfuse ai-gateway litellm-secrets \
  "public_key=LANGFUSE_PUBLIC_KEY secret_key=LANGFUSE_SECRET_KEY host=LANGFUSE_HOST"

echo "== Team app ($APP/$APP-secrets) =="
import_secret "teams/$TEAM/$APP" "$APP" "$APP-secrets" "litellm_api_key=litellm_api_key ingest_token=ingest_token"

echo
echo "Check (sirf keys ke naam, values nahi):"
for p in platform/litellm platform/langfuse "teams/$TEAM/$APP"; do
  kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get -mount=secret -format=json "$p" \
    | python -c "import sys,json;print('  secret/$p:', sorted(json.load(sys.stdin)['data']['data']))"
done
echo "Ab: ./scripts/vault-seed-secrets.sh  (baaki: grafana random, backstage/crossplane 'later')"
