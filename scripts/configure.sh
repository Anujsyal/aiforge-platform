#!/usr/bin/env bash
# Placeholders bharna: <GITHUB_USER> <ACCOUNT_ID> <VPC_ID> <ADMIN_CIDR>
# Usage (repo root se, Git Bash):
#   ./scripts/configure.sh --github-user Anujsyal --vpc-id vpc-0abc... [--account-id 1234...] [--admin-cidr 1.2.3.4/32]
# account-id / admin-cidr na diye to khud detect hote hain. Dobara chala sakta hai (sirf bache placeholders badlega).
set -euo pipefail

GITHUB_USER="" ; VPC_ID="" ; ACCOUNT_ID="" ; ADMIN_CIDR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --github-user) GITHUB_USER="$2"; shift 2 ;;
    --vpc-id)      VPC_ID="$2"; shift 2 ;;
    --account-id)  ACCOUNT_ID="$2"; shift 2 ;;
    --admin-cidr)  ADMIN_CIDR="$2"; shift 2 ;;
    *) echo "unknown flag $1"; exit 1 ;;
  esac
done

[[ -z "$GITHUB_USER" || -z "$VPC_ID" ]] && { echo "Usage: $0 --github-user <user> --vpc-id <vpc-id> [--account-id N] [--admin-cidr IP/32]"; exit 1; }
[[ -z "$ACCOUNT_ID" ]] && ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
[[ -z "$ADMIN_CIDR" ]] && ADMIN_CIDR="$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')/32"

echo "GITHUB_USER=$GITHUB_USER ACCOUNT_ID=$ACCOUNT_ID VPC_ID=$VPC_ID ADMIN_CIDR=$ADMIN_CIDR"

FILES=$(grep -rlE '<GITHUB_USER>|<ACCOUNT_ID>|<VPC_ID>|<ADMIN_CIDR>' gitops backstage charts || true)
for f in $FILES; do
  sed -i -e "s|<GITHUB_USER>|$GITHUB_USER|g" -e "s|<ACCOUNT_ID>|$ACCOUNT_ID|g" \
         -e "s|<VPC_ID>|$VPC_ID|g" -e "s|<ADMIN_CIDR>|$ADMIN_CIDR|g" "$f"
  echo "updated: $f"
done

echo
echo "Bache hue placeholders (khaali hona chahiye):"
grep -rnE '<GITHUB_USER>|<ACCOUNT_ID>|<VPC_ID>|<ADMIN_CIDR>' gitops backstage charts || echo "  none"
