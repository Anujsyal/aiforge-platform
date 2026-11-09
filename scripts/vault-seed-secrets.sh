#!/usr/bin/env bash
# Platform secrets Vault mein. Random wale khud generate; bahar wale (GitHub token, Langfuse, Crossplane AWS key) prompt se.
# Phase 6 order: vault-init.sh → vault-import-existing.sh (LiteLLM + Langfuse + team secrets import) → ye script.
# Import ke baad platform/litellm aur platform/langfuse "skip (exists)" dikhenge = sahi.
# Input `read -s` se (screen pe nahi dikhta, shell history mein nahi jaata).
# Dobara chalana SAFE: jo path pehle se Vault mein hai wo skip (warna LiteLLM master key badal jaati).
# Overwrite karna ho: FORCE=1 ./scripts/vault-seed-secrets.sh
set -euo pipefail
FORCE="${FORCE:-0}"
INIT_FILE="${INIT_FILE:-vault-init.json}"
ROOT_TOKEN=$(python -c "import json;print(json.load(open('$INIT_FILE'))['root_token'])")
vexists() { kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get -mount=secret "$1" >/dev/null 2>&1; }
need() { if [[ "$FORCE" != "1" ]] && vexists "$1"; then echo "  skip $1 (exists)"; return 1; fi; return 0; }
vput() { kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv put "$@" >/dev/null; echo "  wrote $2"; }
rnd() { python -c "import secrets;print(secrets.token_urlsafe($1))"; }
ask() { local v; read -r -s -p "$1: " v; echo >&2; printf '%s' "$v"; }

echo "== Random secrets =="
need platform/litellm && vput -mount=secret platform/litellm master_key="sk-$(rnd 32)" salt_key="sk-$(rnd 32)" postgres_password="$(rnd 24)"
need platform/grafana && vput -mount=secret platform/grafana admin_password="$(rnd 18)"

echo "== Langfuse (Cloud: cloud.langfuse.com → project → Settings → API keys) =="
if need platform/langfuse; then
LF_HOST=$(read -r -p "Langfuse host [https://cloud.langfuse.com]: " h; echo "${h:-https://cloud.langfuse.com}")
LF_PK=$(ask "Langfuse public key (pk-lf-...)")
LF_SK=$(ask "Langfuse secret key (sk-lf-...)")
vput -mount=secret platform/langfuse host="$LF_HOST" public_key="$LF_PK" secret_key="$LF_SK"
fi

echo "== Backstage (GitHub fine-grained PAT: aiforge-platform repo, Contents + Pull requests: Read/Write) =="
if need platform/backstage; then
GH=$(ask "GitHub token (abhi nahi hai to 'later' likh; Phase 8 mein kv patch)")
vput -mount=secret platform/backstage github_token="$GH" postgres_password="$(rnd 24)" backend_secret="$(rnd 32)"
fi

echo "== Crossplane AWS key (Phase 8; IAM user aiforge-crossplane → Security credentials → Create access key) =="
echo "   Abhi nahi chahiye to Enter dabao (skip). Long-lived key zarurat se pehle mat banao; Phase 8 mein ye script dobara chala."
if need platform/crossplane-aws; then
AK=$(ask "Access key ID (Enter = skip)")
if [[ -z "$AK" ]]; then
  echo "  skip platform/crossplane-aws (Phase 8 mein)"
else
  SK=$(ask "Secret access key")
  vput -mount=secret platform/crossplane-aws access_key_id="$AK" secret_access_key="$SK"
fi
fi

echo
echo "Done. ESO 1h mein khud sync karega; turant chahiye to:"
echo "  kubectl annotate externalsecret -A --all force-sync=\$(date +%s) --overwrite"
