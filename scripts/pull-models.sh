#!/usr/bin/env bash
# Local docker-compose ke liye models (pehli baar ~1.6 GB). apps/rag-app folder se chala.
set -euo pipefail
for m in llama3.2:1b qwen2.5:0.5b nomic-embed-text; do
  docker compose exec -T ollama ollama pull "$m"
done
docker compose exec -T ollama ollama list
