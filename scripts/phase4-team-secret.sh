#!/usr/bin/env bash
# PHASE 4 (Vault se pehle): team-alpha ki LiteLLM key haath se + Kubernetes Secret.
# Phase 6 ke baad iski jagah scripts/litellm-onboard-team.sh (Vault wala) use hota hai.
#
# Idempotent: dobara chala sakta hai.
#  - team pehle se hai → wahi use
#  - "team-alpha-rag" alias wali purani keys (bina team / galat team) → delete, phir ek nayi key
#  - namespace / secret pehle se hai → update
#
# Usage:  ./scripts/phase4-team-secret.sh [team=team-alpha] [app=team-alpha-rag] [budget=25]
# Pehle:  tunnel chalu ho (scripts/tunnel.sh)
set -euo pipefail
TEAM="${1:-team-alpha}"; APP="${2:-team-alpha-rag}"; BUDGET="${3:-25}"
PORT=4012

kubectl -n ai-gateway port-forward svc/litellm $PORT:4000 >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
sleep 4

MK=$(kubectl -n ai-gateway get secret litellm-secrets -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)
[[ ${#MK} -gt 10 ]] || { echo "LiteLLM master key nahi mili"; exit 1; }
api() { curl -fsS -H "Authorization: Bearer $MK" -H 'Content-Type: application/json' "$@"; }
# Windows Python file path nahi padh paata → hamesha stdin se JSON
py() { python -c "$1"; }

# --- 1. Team ---
TEAM_ID=$(api "localhost:$PORT/team/list" | py "
import sys,json
print(next((t['team_id'] for t in json.load(sys.stdin) if t.get('team_alias')=='$TEAM'), ''))")
if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID=$(api -X POST "localhost:$PORT/team/new" -d "{\"team_alias\":\"$TEAM\",\"max_budget\":$BUDGET,\"budget_duration\":\"30d\",\"models\":[\"llama3.2-1b\",\"qwen2.5-0.5b\",\"nomic-embed-text\"]}" \
    | py "import sys,json;print(json.load(sys.stdin)['team_id'])")
  echo "Team bani: $TEAM ($TEAM_ID)"
else
  echo "Team pehle se: $TEAM ($TEAM_ID)"
fi

# --- 2. Purani keys (isi alias wali) delete ---
OLD=$(api "localhost:$PORT/key/list?return_full_object=true&key_alias=$APP" | py "
import sys,json
d=json.load(sys.stdin)
print(json.dumps([k['token'] for k in d.get('keys',[]) if k.get('key_alias')=='$APP']))")
if [[ "$OLD" != "[]" ]]; then
  api -X POST "localhost:$PORT/key/delete" -d "{\"keys\":$OLD}" >/dev/null && echo "Purani keys delete: $OLD" | sed 's/[0-9a-f]\{20,\}/<hash>/g'
fi

# --- 3. Nayi key (team se judi) ---
APP_KEY=$(api -X POST "localhost:$PORT/key/generate" -d "{\"team_id\":\"$TEAM_ID\",\"key_alias\":\"$APP\"}" \
  | py "import sys,json;print(json.load(sys.stdin)['key'])")
echo "Nayi key bani (length ${#APP_KEY}), team $TEAM se judi"

# --- 4. Namespace + Secret ---
kubectl create ns "$APP" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label ns "$APP" --overwrite aiforge.io/tenant=true "aiforge.io/team=$TEAM" \
  pod-security.kubernetes.io/enforce=restricted >/dev/null
INGEST=$(python -c 'import secrets;print(secrets.token_urlsafe(24))')
kubectl -n "$APP" create secret generic "$APP-secrets" \
  --from-literal=litellm_api_key="$APP_KEY" --from-literal=ingest_token="$INGEST" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "Namespace $APP + Secret $APP-secrets ready"
echo
echo "INGEST token (note kar le, ALB se /ingest ke liye): $INGEST"
