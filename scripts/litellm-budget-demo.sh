#!/usr/bin/env bash
# FinOps demo: team ka LLM budget khatam → gateway naye requests rokta hai → app HTTP 429.
#   1. team ka current max_budget yaad rakho
#   2. max_budget = 0.000001 (practically zero)
#   3. /ask via ALB → 429 "team LLM budget exceeded"
#   4. purana budget WAPAS (trap: script beech mein ruke tab bhi)
# Master key sirf memory mein; print nahi hoti.
#
# Pehle: kubectl -n ai-gateway port-forward svc/litellm 4000:4000   (alag terminal)
# Usage: ./scripts/litellm-budget-demo.sh [team=team-beta] [app=team-beta-faq]
set -euo pipefail
TEAM="${1:-team-beta}"; APP="${2:-team-beta-faq}"
LITELLM="${LITELLM_URL:-http://localhost:4000}"
ALB="${ALB:-$(kubectl -n "$APP" get ingress "$APP" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')}"
MASTER=$(kubectl -n ai-gateway get secret litellm-secrets -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)
api() { curl -fsS -H "Authorization: Bearer $MASTER" -H 'Content-Type: application/json' "$@"; }

read -r TEAM_ID OLD_BUDGET SPEND < <(api "$LITELLM/team/list" | python -c "
import sys, json
for t in json.load(sys.stdin):
    if t.get('team_alias') == '$TEAM':
        print(t['team_id'], t.get('max_budget'), t.get('spend') or 0); break
else:
    sys.exit('team $TEAM nahi mili')")
echo "Team $TEAM ($TEAM_ID): budget \$$OLD_BUDGET, spend abhi tak \$$SPEND"

restore() {
  api -X POST "$LITELLM/team/update" -d "{\"team_id\":\"$TEAM_ID\",\"max_budget\":$OLD_BUDGET}" >/dev/null \
    && echo "Restored: budget wapas \$$OLD_BUDGET"
}
trap restore EXIT

api -X POST "$LITELLM/team/update" -d "{\"team_id\":\"$TEAM_ID\",\"max_budget\":0.000001}" >/dev/null
echo "Budget → \$0.000001 (khatam). LiteLLM cache update ke liye 20s..."
sleep 20

for i in 1 2; do
  code=$(curl -s -m 120 -o /tmp/budget-demo.json -w '%{http_code}' -X POST "http://$ALB/apps/$APP/ask" \
    -H 'content-type: application/json' -d '{"question":"What is the name of the platform on-call rotation?"}' || true)
  echo "  /ask → HTTP $code  $(head -c 120 /tmp/budget-demo.json 2>/dev/null)"
  [[ "$code" == "429" ]] && break
  sleep 15
done
