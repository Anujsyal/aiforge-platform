# AIForge: proof of the live run (Nov 2026)

The platform ran on AWS ap-south-1 (4-node k3s, 24 Argo CD apps) and was then destroyed to save cost.
This folder keeps screenshots from the build; [`../evidence/`](../evidence/) keeps terminal output captured from the live cluster just before teardown (`scripts/capture-evidence.sh`).

## Screenshots

| File | Phase | Shows |
|---|---|---|
| `05-ci-run-eval-gate.png` | 5 | GitHub Actions run (`rag-app-ci`) with eval gate summary |
| `05-cosign-verify-attestation.png` | 5 | `cosign verify-attestation`: signed by this repo's `rag-app-ci.yml@main`, predicate `gatePassed: true, passRate 0.917, redteamPassRate 1` |
| `06-vault-init-and-secret-import.png` | 6 | Vault init/unseal, live secrets imported (key names only) |
| `06-vault-seed-eso-clustersecretstore.png` | 6 | Seed script + ClusterSecretStore `Valid / READY True` |
| `06-kyverno-policies-ready-default-deny.png` | 6 | 7 Kyverno ClusterPolicies Ready + generated `default-deny-all` |
| `06-networkpolicy-openai-blocked-ollama-refused.png` | 6 | Pod → api.openai.com unreachable, → Ollama refused, → LiteLLM alive |
| `07-langfuse-traces.png` | 7 | Langfuse: `rag-answer` generation (prompt, output), embeddings, app OTel spans |
| `07-loki-explore-logs.png` | 7 | Grafana Explore → Loki `{namespace="team-alpha-rag"}` |
| `07-grafana-rag-dashboard.png` | 7 | Dashboard "AIForge / RAG apps + cost": p95, tokens/min, Qdrant latency |
| `08-crossplane-vectorstore-created.png` | 8 | `VectorStore` → Qdrant collection + ConfigMap + S3 bucket + public access block |
| `08-crossplane-cleanup-after-deadlock.png` | 8 | Namespace-deletion deadlock recovery (collection DELETE + finalizer) |
| `08-backstage-catalog-component.png` | 8 | Backstage component page: owner, system, consumed LLM API, model catalog deps |
| `08-golden-path-team-beta-resources.png` | 8 | App from the Backstage form: VectorStore READY, ExternalSecret synced, pod running |
| `09-budget-demo-start.png` | 9 | Budget demo (team budget → ~0 → HTTP 429 → restored) |
| `09-opencost-ui.png` | 9 | OpenCost: cost by namespace, efficiency 22.5% |
| `09-showback-report.png` | 9 | Showback: LiteLLM spend + OpenCost infra cost per team |
| `09-sns-publish.png` | 9 | SNS test publish (budget alert path) |
| `10-argocd-24-apps-selfheal.png` | 10 | 24 Argo CD apps Synced/Healthy + self-heal (scale 0 → back to 1) |

## Terminal evidence (`../evidence/`)

| File | Shows |
|---|---|
| `01-aws-infra.txt` | Subnets (2 AZ public/private), NAT, VPC endpoints, 4 instances (private IP only, IMDSv2 required), ALB |
| `02-cluster-gitops.txt` | Nodes with pool / instance-type / zone labels and `aws:///` providerIDs, 24 Argo apps, ApplicationSet, namespace labels (team, tenant, PSA) |
| `03-ai-serving-and-apps.txt` | Ollama models, LiteLLM/Qdrant pods, `/ask` on both tenant apps (llama3.2-1b vs qwen2.5-0.5b), prompt-injection blocked by guardrail |
| `04-supply-chain-security.txt` | Release pin (tag + digest), CI release commits, Kyverno `verify-images: pass` on both apps, denials (unsigned image, Docker Hub, `OPENAI_API_KEY`), PSA denial, NetworkPolicy results, ExternalSecrets synced, Vault status |
| `05-observability.txt` | Prometheus targets all up, RAG metrics, alert rules, Loki namespaces, ServiceMonitors, Langfuse 401 count = 0 |
| `06-platform-layer.txt` | Crossplane providers/functions healthy, XRD + Composition, VectorStores + Requests, Backstage pods, golden-path generated files, PRs #1 (merged) / #2 (closed) |
| `07-finops.txt` | AWS Budgets spend, FinOps tags on instances, Infracost comment (+$158/month) |

Screenshots not kept here (contain partial keys or personal data): Langfuse API key page, Gmail alert, Crossplane key ID output, terminals showing the home IP.
