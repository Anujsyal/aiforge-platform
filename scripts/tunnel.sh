#!/usr/bin/env bash
# SSM port forward: laptop localhost:6443 → k3s server (private subnet) :6443
# Koi public IP nahi, port 22 nahi, SSH key nahi. IAM se auth, CloudTrail mein audit.
# Zarurat: AWS CLI + Session Manager plugin (guide 1.3). Terminal khula rakh.
set -euo pipefail
REGION="${AWS_REGION:-ap-south-1}"
SERVER_ID="${1:-$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Role,Values=k3s-server" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)}"

[[ "$SERVER_ID" == "None" || -z "$SERVER_ID" ]] && { echo "k3s server running nahi mila"; exit 1; }
echo "Tunnel: localhost:6443 → $SERVER_ID:6443  (Ctrl+C se band)"
aws ssm start-session --region "$REGION" --target "$SERVER_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6443"],"localPortNumber":["6443"]}'
