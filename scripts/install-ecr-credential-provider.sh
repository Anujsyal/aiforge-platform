#!/usr/bin/env bash
# k3s nodes pe ECR login ka plugin (asli run 2026-11-09 mein pakdi gayi problem):
#   "failed to pull ... authorization failed: no basic auth credentials"
# EKS pe kubelet ke paas ecr-credential-provider pehle se hota hai; k3s pe NAHI. Node IAM role pe
# ECR read permission hone ke bawajood containerd ko ECR token nahi milta.
# k3s /var/lib/rancher/credentialprovider/{bin,config.yaml} khud dhoondhta hai → bas wahan rakhna + restart.
#
# Ye script chalte hue nodes pe SSM Run Command se install karta hai (naye nodes ke liye Terraform
# user-data mein same steps hain).  Usage: ./scripts/install-ecr-credential-provider.sh
set -euo pipefail
REGION="${AWS_REGION:-ap-south-1}"
VER="${ECR_CP_VERSION:-v1.37.0}"   # k8s minor se match (kubernetes/cloud-provider-aws releases)

IDS=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Project,Values=aiforge" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
[[ -z "$IDS" ]] && { echo "running aiforge instances nahi mile"; exit 1; }
echo "Nodes: $IDS"

# Node pe chalne wali script (k3s server pe service "k3s", agents pe "k3s-agent")
read -r -d '' REMOTE <<EOF || true
set -e
D=/var/lib/rancher/credentialprovider
mkdir -p \$D/bin
curl -sfL -o \$D/bin/ecr-credential-provider https://artifacts.k8s.io/binaries/cloud-provider-aws/$VER/linux/amd64/ecr-credential-provider-linux-amd64
chmod 755 \$D/bin/ecr-credential-provider
cat > \$D/config.yaml <<'CFG'
apiVersion: kubelet.config.k8s.io/v1
kind: CredentialProviderConfig
providers:
  - name: ecr-credential-provider
    matchImages:
      - "*.dkr.ecr.*.amazonaws.com"
    defaultCacheDuration: "12h"
    apiVersion: credentialprovider.kubelet.k8s.io/v1
CFG
if systemctl list-unit-files | grep -q '^k3s.service'; then systemctl restart k3s; else systemctl restart k3s-agent; fi
sleep 5
echo "OK \$(hostname): \$(\$D/bin/ecr-credential-provider --version 2>/dev/null || echo installed)"
EOF

PARAMS=$(python -c "import json,sys;print(json.dumps({'commands':[sys.argv[1]]}))" "$REMOTE")
# MSYS_NO_PATHCONV: JSON ke andar /var/lib/... ko Git Bash Windows path na banaye
CID=$(MSYS_NO_PATHCONV=1 aws ssm send-command --region "$REGION" --instance-ids $IDS \
  --document-name AWS-RunShellScript --comment "install ecr-credential-provider" \
  --parameters "$PARAMS" --query Command.CommandId --output text)
echo "SSM command: $CID  (40-60s)"
sleep 45
for i in $IDS; do
  for try in 1 2 3 4 5 6; do
    OUT=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CID" --instance-id "$i" \
      --query '[Status,StandardOutputContent,StandardErrorContent]' --output text 2>/dev/null || true)
    case "$OUT" in Success*|Failed*) break ;; esac
    sleep 10
  done
  echo "--- $i"; echo "$OUT" | tail -3
done
echo
echo "Ab: kubectl -n team-alpha-rag delete pod --all   (pods naye credentials ke saath dobara pull karenge)"
