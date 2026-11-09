#!/usr/bin/env bash
# Crossplane (provider-aws-s3) ke IAM user ki access key banao aur SEEDHA Vault mein daalo.
# Secret kabhi screen / clipboard / shell history / Terraform state mein nahi aata:
#   aws iam create-access-key (JSON stdout) → python (sirf 2 fields) → vault kv put ... - (stdin)
#
# Kyun aisa: Phase 7 mein Langfuse secret key copy-paste galat hua → 401 (asli run). Aur Terraform se
# key banate to secret tfstate (S3) mein plaintext jaata (Problems faced #23).
# k3s pe IRSA nahi hai, isliye long-lived key hai: ROTATE karna (ye script dobara chala, purani delete kar).
#
# Usage: ./scripts/crossplane-aws-key.sh            (key pehle se Vault mein ho to ruk jaata hai)
#        ROTATE=1 ./scripts/crossplane-aws-key.sh   (nayi key → Vault → purani AWS key delete)
set -euo pipefail
USER_NAME="${USER_NAME:-aiforge-crossplane}"
ROTATE="${ROTATE:-0}"
INIT_FILE="${INIT_FILE:-vault-init.json}"
ROOT_TOKEN=$(python -c "import json;print(json.load(open('$INIT_FILE'))['root_token'])")
vault_() { kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault "$@"; }

if vault_ kv get -mount=secret platform/crossplane-aws </dev/null >/dev/null 2>&1 && [[ "$ROTATE" != "1" ]]; then
  echo "secret/platform/crossplane-aws pehle se hai. Rotate: ROTATE=1 $0"; exit 0
fi

OLD=$(aws iam list-access-keys --user-name "$USER_NAME" --query 'AccessKeyMetadata[].AccessKeyId' --output text)
N=$(wc -w <<<"$OLD")
if [[ "$N" -ge 2 ]]; then echo "ERROR: $USER_NAME ki pehle se 2 keys hain (AWS limit). Ek delete kar: $OLD"; exit 1; fi

echo "Creating access key for $USER_NAME (value print nahi hogi)..."
aws iam create-access-key --user-name "$USER_NAME" --output json \
  | python -c "
import sys, json
k = json.load(sys.stdin)['AccessKey']
print(json.dumps({'access_key_id': k['AccessKeyId'], 'secret_access_key': k['SecretAccessKey']}))" \
  | vault_ kv put -mount=secret platform/crossplane-aws - >/dev/null
echo "  wrote secret/platform/crossplane-aws (access_key_id, secret_access_key)"

if [[ "$ROTATE" == "1" && -n "$OLD" ]]; then
  for k in $OLD; do aws iam delete-access-key --user-name "$USER_NAME" --access-key-id "$k"; echo "  deleted old key $k"; done
fi
NEW=$(aws iam list-access-keys --user-name "$USER_NAME" --query 'AccessKeyMetadata[].AccessKeyId' --output text)
echo "AWS keys ab: $NEW  (ID secret nahi hai; secret part sirf Vault mein)"
echo "ESO sync:  kubectl -n crossplane-system annotate externalsecret aws-crossplane-creds force-sync=\$(date +%s) --overwrite"
