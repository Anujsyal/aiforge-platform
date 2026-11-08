#!/usr/bin/env bash
# SSM port forward: laptop localhost:6443 → k3s server (private subnet) :6443
# Koi public IP nahi, port 22 nahi, SSH key nahi. IAM se auth, CloudTrail mein audit.
# Zarurat: AWS CLI + Session Manager plugin (guide 1.3). Terminal khula rakh.
#
# 2 problems jo asli run mein aaye (2026-11-08):
#  1. SSM session ~20 min IDLE pe AWS band kar deta hai. Kabhi plugin exit ho jaata hai, kabhi laptop pe
#     khula reh jaata hai (connection accept karke turant cut: "TLS handshake timeout").
#  2. Laptop sleep / restart / Wi-Fi change pe bhi session toot-ta hai.
# Fix: (a) KEEPALIVE: har 4 min curl se thoda traffic → session idle nahi hota
#      (b) AUTO-RECONNECT: plugin exit hua to 3s mein naya session
# Band karna: Ctrl+C (do baar dabana pad sakta hai).
set -uo pipefail
REGION="${AWS_REGION:-ap-south-1}"
SERVER_ID="${1:-$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Role,Values=k3s-server" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)}"

[[ "$SERVER_ID" == "None" || -z "$SERVER_ID" ]] && { echo "k3s server running nahi mila (instances stopped?)"; exit 1; }

# Keepalive (background). /livez bina auth ke bhi response deta hai; humein bas traffic chahiye.
( while true; do sleep 240; curl -sk -m 10 -o /dev/null https://127.0.0.1:6443/livez || true; done ) &
KEEPALIVE_PID=$!
trap 'kill $KEEPALIVE_PID 2>/dev/null; echo; echo "Tunnel band."; exit 0' INT TERM

while true; do
  echo "[$(date +%H:%M:%S)] Tunnel: localhost:6443 → $SERVER_ID:6443  (Ctrl+C se band)"
  aws ssm start-session --region "$REGION" --target "$SERVER_ID" \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["6443"],"localPortNumber":["6443"]}'
  echo "[$(date +%H:%M:%S)] Session khatam (idle timeout / network). 3s mein reconnect..."
  sleep 3
done
