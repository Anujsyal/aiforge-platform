#!/usr/bin/env bash
# Vault ke EK path ki sirf chuni hui keys badlo (baaki keys same rehti hain = `vault kv patch`).
# Values prompt se (`read -s`: screen pe nahi dikhti, shell history mein nahi jaati), stdin JSON se Vault tak.
#
# Kyun: vault-seed-secrets.sh existing path skip karta hai, aur FORCE=1 SAARE random secrets dobara banata hai
# (LiteLLM master/salt key badli = DB ki keys bekaar). Ek secret update karne ka safe tareeka ye hai.
#
# Examples:
#   ./scripts/vault-patch-secret.sh platform/langfuse public_key secret_key host     # Phase 7
#   ./scripts/vault-patch-secret.sh platform/backstage github_token                  # Phase 8
# Baad mein ESO sync + consumer restart (script batata hai).
set -euo pipefail
PATH_="${1:?vault path, jaise platform/langfuse}"; shift
[[ $# -ge 1 ]] || { echo "kam se kam ek key ka naam do"; exit 1; }
INIT_FILE="${INIT_FILE:-vault-init.json}"
ROOT_TOKEN=$(python -c "import json;print(json.load(open('$INIT_FILE'))['root_token'])")

vault_() { kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault "$@"; }
vault_ kv get -mount=secret "$PATH_" >/dev/null 2>&1 || { echo "secret/$PATH_ Vault mein nahi hai (pehle seed/import)"; exit 1; }

declare -A VALS
for k in "$@"; do
  read -r -s -p "  $k (input chhupa rahega, Enter = mat badlo): " v; echo >&2
  [[ -n "$v" ]] && VALS[$k]="$v"
done
[[ ${#VALS[@]} -gt 0 ]] || { echo "Kuch nahi badla."; exit 0; }

# bash assoc array → JSON (python ko env ke through, command line pe values nahi)
JSON=$(for k in "${!VALS[@]}"; do printf '%s\0%s\0' "$k" "${VALS[$k]}"; done | python -c "
import sys, json
parts = sys.stdin.buffer.read().split(b'\0')[:-1]
print(json.dumps({parts[i].decode(): parts[i+1].decode() for i in range(0, len(parts), 2)}))")
printf '%s' "$JSON" | vault_ kv patch -mount=secret "$PATH_" - >/dev/null
unset JSON VALS
echo "  patched secret/$PATH_: ${*}"

echo
# -i ke bina (terminal ka stdin na pakde); sirf keys ke naam
kubectl -n vault exec vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get -mount=secret -format=json "$PATH_" </dev/null \
  | python -c "import sys,json;print('  keys:', sorted(json.load(sys.stdin)['data']['data']))" || echo "  (keys list nahi mili; patch ho chuka hai)"
echo "ESO turant sync:  kubectl annotate externalsecret -A --all force-sync=\$(date +%s) --overwrite"
echo "Phir jo isko use karta hai use restart karo (env sirf start pe padhi jaati hai)."
