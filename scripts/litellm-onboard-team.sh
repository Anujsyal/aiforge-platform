#!/usr/bin/env bash
# Team + app onboarding (platform admin chalata hai, Backstage PR ke checklist se):
#   1. LiteLLM mein team (monthly budget, allowed models)   [idempotent: team pehle se ho to reuse]
#   2. App ke liye virtual key (team se bandhi, alias = app name)
#   3. Key + ingest token Vault mein: secret/teams/<team>/<app>  → ESO → app ka Secret
# Developer ko key kabhi dikhti nahi.
#
# Usage: ./scripts/litellm-onboard-team.sh <team> <app> [monthly_budget_usd=25] [chat_model=llama3.2-1b]
# Pehle: kubectl -n ai-gateway port-forward svc/litellm 4000:4000   (alag terminal)
set -euo pipefail
TEAM="${1:?team}" ; APP="${2:?app}" ; BUDGET="${3:-25}" ; MODEL="${4:-llama3.2-1b}"
LITELLM="${LITELLM_URL:-http://localhost:4000}"
INIT_FILE="${INIT_FILE:-vault-init.json}"

MASTER=$(kubectl -n ai-gateway get secret litellm-secrets -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)
ROOT_TOKEN=$(python -c "import json;print(json.load(open('$INIT_FILE'))['root_token'])")
api() { curl -fsS -H "Authorization: Bearer $MASTER" -H 'Content-Type: application/json' "$@"; }

# --- 1. Team ---
TEAM_ID=$(api "$LITELLM/team/list" | python -c "
import sys,json
for t in json.load(sys.stdin):
    if t.get('team_alias')=='$TEAM': print(t['team_id']); break")
if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID=$(api -X POST "$LITELLM/team/new" -d "{
    \"team_alias\": \"$TEAM\",
    \"max_budget\": $BUDGET,
    \"budget_duration\": \"30d\",
    \"models\": [\"$MODEL\", \"qwen2.5-0.5b\", \"nomic-embed-text\"],
    \"tpm_limit\": 20000,
    \"rpm_limit\": 60,
    \"metadata\": {\"cost_center\": \"$TEAM\"}
  }" | python -c "import sys,json;print(json.load(sys.stdin)['team_id'])")
  echo "Created team $TEAM ($TEAM_ID), budget \$$BUDGET / 30d"
else
  echo "Team $TEAM exists ($TEAM_ID)"
fi

# --- 2. Key (har app ki alag key: app-level spend + revoke) ---
KEY=$(api -X POST "$LITELLM/key/generate" -d "{
  \"team_id\": \"$TEAM_ID\",
  \"key_alias\": \"$APP\",
  \"models\": [\"$MODEL\", \"qwen2.5-0.5b\", \"nomic-embed-text\"],
  \"metadata\": {\"app\": \"$APP\", \"team\": \"$TEAM\"}
}" | python -c "import sys,json;print(json.load(sys.stdin)['key'])")

# --- 3. Vault ---
INGEST=$(python -c "import secrets;print(secrets.token_urlsafe(24))")
kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" \
  vault kv put -mount=secret "teams/$TEAM/$APP" litellm_api_key="$KEY" ingest_token="$INGEST" >/dev/null

echo "Vault: secret/teams/$TEAM/$APP  (litellm_api_key, ingest_token)"
echo "Key value print nahi ki (jaan-boojh ke). ESO sync: kubectl -n $APP annotate externalsecret $APP-secrets force-sync=\$(date +%s) --overwrite"
