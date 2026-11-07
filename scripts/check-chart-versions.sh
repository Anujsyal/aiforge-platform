#!/usr/bin/env bash
# gitops/platform/*.yaml mein pinned Helm chart versions vs Artifact Hub latest.
# Upgrade karne se pehle release notes padh (major bump = breaking changes ho sakte hain).
set -euo pipefail
declare -A HUB=(
  [aws-load-balancer-controller]=aws/aws-load-balancer-controller
  [kyverno]=kyverno/kyverno
  [external-secrets]=external-secrets-operator/external-secrets
  [vault]=hashicorp/vault
  [crossplane]=crossplane/crossplane
  [kube-prometheus-stack]=prometheus-community/kube-prometheus-stack
  [qdrant]=qdrant/qdrant
  [opentelemetry-collector]=opentelemetry-helm/opentelemetry-collector
  [loki]=grafana/loki
  [alloy]=grafana/alloy
  [opencost]=opencost/opencost
)
printf "%-30s %-14s %-14s\n" CHART PINNED LATEST
for f in gitops/platform/*.yaml; do
  python - "$f" <<'EOF' | while read -r chart pinned; do
import sys, re
txt = open(sys.argv[1], encoding="utf-8").read()
for m in re.finditer(r"chart:\s*(\S+)\s*\n\s*targetRevision:\s*(\S+)", txt):
    print(m.group(1), m.group(2))
EOF
    pkg="${HUB[$chart]:-}"
    latest="?"
    [[ -n "$pkg" ]] && latest=$(curl -s "https://artifacthub.io/api/v1/packages/helm/$pkg" | python -c "import sys,json;print(json.load(sys.stdin).get('version','?'))")
    flag=""; [[ "$latest" != "$pinned" ]] && flag="  <-- check"
    printf "%-30s %-14s %-14s%s\n" "$chart" "$pinned" "$latest" "$flag"
  done
done
