#!/bin/bash
# k3s AGENT bootstrap (Terraform templatefile). Log: /var/log/k3s-bootstrap.log
set -euo pipefail
exec > >(tee -a /var/log/k3s-bootstrap.log) 2>&1
echo "=== k3s agent bootstrap start: $(date -Is) ==="

REGION="${region}"
SERVER_IP="${server_ip}"

snap install aws-cli --classic
export PATH=$PATH:/snap/bin

IMDS_TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
md() { curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" "http://169.254.169.254/latest/meta-data/$1"; }
INSTANCE_ID=$(md instance-id)
AZ=$(md placement/availability-zone)
INSTANCE_TYPE=$(md instance-type)
NODE_NAME=$(hostname -f)

K3S_TOKEN=$(aws ssm get-parameter --region "$REGION" --name "${token_param}" --with-decryption --query Parameter.Value --output text)

# Server ka API aane tak wait (server ~2-3 min leta hai)
echo "Waiting for k3s server $SERVER_IP:6443 ..."
until (echo > /dev/tcp/$SERVER_IP/6443) 2>/dev/null; do sleep 5; done

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${k3s_version}" K3S_TOKEN="$K3S_TOKEN" K3S_URL="https://$SERVER_IP:6443" sh -s - agent \
  --node-name "$NODE_NAME" \
  --kubelet-arg "provider-id=aws:///$AZ/$INSTANCE_ID" \
  --node-label "node.kubernetes.io/instance-type=$INSTANCE_TYPE" \
  --node-label "topology.kubernetes.io/region=$REGION" \
  --node-label "topology.kubernetes.io/zone=$AZ" \
  --node-label "aiforge.io/pool=${node_pool}"

echo "=== Worker joined: $(date -Is) ==="
