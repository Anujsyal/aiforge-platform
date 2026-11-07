#!/bin/bash
# k3s SERVER bootstrap (Terraform templatefile). Log: /var/log/k3s-bootstrap.log
# Note: is file mein bash variables bina curly braces ke likhe hain ($VAR), kyunki
# dollar + curly brace Terraform ka template syntax hai (Terraform values wahi se aate hain).
set -euo pipefail
exec > >(tee -a /var/log/k3s-bootstrap.log) 2>&1
echo "=== k3s server bootstrap start: $(date -Is) ==="

REGION="${region}"

# --- 1. AWS CLI (SSM parameters ke liye) ---
snap install aws-cli --classic
export PATH=$PATH:/snap/bin

# --- 2. IMDSv2 se instance info ---
IMDS_TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
md() { curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" "http://169.254.169.254/latest/meta-data/$1"; }
INSTANCE_ID=$(md instance-id)
AZ=$(md placement/availability-zone)
INSTANCE_TYPE=$(md instance-type)
NODE_NAME=$(hostname -f)

# --- 3. Join token SSM se (user data mein secret nahi likha) ---
K3S_TOKEN=$(aws ssm get-parameter --region "$REGION" --name "${token_param}" --with-decryption --query Parameter.Value --output text)

# --- 4. k3s install ---
#  --disable traefik/servicelb : ingress ke liye AWS ALB use karenge
#  provider-id                 : ALB controller (instance targets) + OpenCost ko EC2 instance pata chale
#  instance-type/zone labels   : OpenCost pricing ke liye (k3s mein cloud controller nahi jo ye labels lagaye)
#  --secrets-encryption        : datastore mein Secrets encrypted at rest
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${k3s_version}" K3S_TOKEN="$K3S_TOKEN" sh -s - server \
  --node-name "$NODE_NAME" \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 600 \
  --tls-san 127.0.0.1 \
  --secrets-encryption \
  --kubelet-arg "provider-id=aws:///$AZ/$INSTANCE_ID" \
  --node-label "node.kubernetes.io/instance-type=$INSTANCE_TYPE" \
  --node-label "topology.kubernetes.io/region=$REGION" \
  --node-label "topology.kubernetes.io/zone=$AZ" \
  --node-label "aiforge.io/pool=system"

# --- 5. Node Ready hone tak ruk ---
for i in $(seq 1 60); do
  if /usr/local/bin/k3s kubectl get node "$NODE_NAME" 2>/dev/null | grep -q " Ready"; then break; fi
  sleep 5
done

# --- 6. Kubeconfig SSM mein upload ---
# Server address 127.0.0.1 hi rehta hai: laptop SSM port-forward (localhost:6443) se aayega.
aws ssm put-parameter --region "$REGION" --name "${kubeconfig_param}" --type SecureString \
  --tier Intelligent-Tiering --overwrite --value "file:///etc/rancher/k3s/k3s.yaml"

echo "=== Control plane bootstrap complete: $(date -Is) ==="
