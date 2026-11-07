#!/usr/bin/env bash
# k3s server ne apna kubeconfig SSM Parameter Store (SecureString) mein daala hai. Wahan se laptop pe.
# Server address 127.0.0.1:6443 hai → scripts/tunnel.sh (SSM port forward) chalu hona chahiye.
set -euo pipefail
REGION="${AWS_REGION:-ap-south-1}"
PARAM="${KUBECONFIG_PARAM:-/aiforge/k3s/kubeconfig}"
OUT="${HOME}/.kube/aiforge.yaml"

mkdir -p "$(dirname "$OUT")"
# MSYS_NO_PATHCONV sirf isi command pe: Git Bash "/aiforge/k3s/kubeconfig" ko "C:/Program Files/Git/aiforge/..."
# bana deta hai → ParameterNotFound. Globally mat lagana: phir KUBECONFIG jaise env vars bhi convert nahi hote.
MSYS_NO_PATHCONV=1 aws ssm get-parameter --region "$REGION" --name "$PARAM" --with-decryption \
  --query Parameter.Value --output text > "$OUT"
chmod 600 "$OUT" 2>/dev/null || true

# k3s ka default context naam "default" hota hai → readable naam
sed -i 's/: default$/: aiforge/; s/name: default$/name: aiforge/' "$OUT"

echo "Kubeconfig: $OUT"
echo "Ab:  export KUBECONFIG=$OUT   (PowerShell: \$env:KUBECONFIG=\"$OUT\")"
echo "Tunnel alag terminal mein: ./scripts/tunnel.sh"
