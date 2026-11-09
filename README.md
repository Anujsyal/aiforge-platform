# AIForge: Self-Service AI Platform on AWS

A self-service AI platform on AWS with secure VPC networking, a central LLM gateway, golden paths for RAG apps, eval gates, shadow-AI controls and per-team cost showback.

```
Backstage "Create RAG App" ─► PR ─► Argo CD ApplicationSet ─► Helm "ai-app" ─► tenant namespace
                                                                   │
  RAG app (FastAPI + LangChain) ─► LiteLLM gateway (keys, budgets, fallback, spend) ─► Ollama (llama3.2:1b, qwen2.5:0.5b, nomic-embed-text)
          │                                   └─► Langfuse traces
          └─► Qdrant (Crossplane VectorStore API)

CI: gitleaks → pytest → Trivy → promptfoo eval + red-team (+RAGAS) → cosign sign + eval attestation → GitOps bump
Admission: Kyverno (signed + eval-passed images, ECR only, no external AI keys) · PSA restricted · default-deny NetworkPolicy
Infra: Terraform → VPC (2 AZ, private subnets, NAT, NACLs, endpoints, flow logs) → k3s on EC2 (SSM only) → ALB
Cost: LiteLLM per-team spend · OpenCost per namespace · Infracost on PRs · AWS Budgets + SNS
```

## Docs
(Word copies: `docs/word/*.docx`, `python scripts/docs-to-docx.py` se regenerate)
- **[MANUAL-SETUP-GUIDE.md](MANUAL-SETUP-GUIDE.md)**: phase-by-phase build (manual + code), troubleshooting, cleanup
- **[docs/PROJECT-EXPLAINED.md](docs/PROJECT-EXPLAINED.md)**: how it works, tool connections, design trade-offs, problems, interview Q&A
- **[docs/screenshots/](docs/screenshots/)** + **[docs/evidence/](docs/evidence/)**: screenshots and terminal output from the live run (before teardown)
- **[docs/BUILD-JOURNEY.md](docs/BUILD-JOURNEY.md)**: the real build diary: order of work, how the pieces connect, every error hit and its fix, day-to-day operations

## Stack
Terraform · AWS VPC/NAT/NACL/SG/VPC endpoints/Flow Logs/SSM/ECR/Budgets/SNS · k3s · AWS Load Balancer Controller · Ollama · LiteLLM · FastAPI · LangChain · Qdrant · Backstage · Crossplane v2 · Helm · Argo CD + ApplicationSets · GitHub Actions · promptfoo · RAGAS · Trivy · gitleaks · cosign · Kyverno · NetworkPolicies · Vault + External Secrets · Pod Security Admission · Langfuse · OpenTelemetry · Prometheus · Grafana · Loki + Alloy · OpenCost · Infracost

Also used in the real run: AWS IAM (GitHub OIDC role, IMDSv2 node role), SSM Parameter Store, CloudTrail (OIDC debugging), Cost Explorer + Pricing API (cost checks) · ecr-credential-provider (k3s ↔ ECR) · flannel + kube-router (k3s CNI / NetworkPolicy) · local-path provisioner · Kustomize · PostgreSQL (LiteLLM, Backstage) · Sigstore Fulcio/Rekor (keyless signing) · Crossplane provider-http + provider-aws-s3 · Docker / docker compose · pytest · app-level guardrails · fnm + corepack/yarn (Backstage build) · pandoc (Word copies of docs)

## Repo layout
| Path | Contents |
|---|---|
| `terraform/` | bootstrap (state bucket), modules (vpc, k3s-cluster, ecr, github-oidc, budgets), stacks/platform |
| `apps/rag-app/` | FastAPI RAG service, tests, sample docs, docker-compose |
| `evals/` | Golden dataset, promptfoo quality + red-team, RAGAS, attestation builder |
| `charts/ai-app/` | Golden-path Helm chart |
| `gitops/` | Argo CD bootstrap, platform apps, platform config, ApplicationSet, tenant apps, release pin |
| `backstage/` | Catalog (incl. model catalog), "Create RAG App" template, app-config |
| `.github/workflows/` | RAG app CI + eval gate, Terraform CI + Infracost, Backstage image |
| `scripts/` | Kubeconfig/SSM tunnel, Vault init/seed, team onboarding, showback report |

## Status
All 10 phases built and run on AWS (Nov 2026): 4-node k3s cluster, 24 Argo CD applications (app-of-apps) Synced/Healthy, two tenant RAG apps (one created end-to-end from the Backstage golden path). Every real problem hit during the build (74 entries) is documented with root cause and fix in [docs/PROJECT-EXPLAINED.md](docs/PROJECT-EXPLAINED.md#8-problems-faced-aur-fix) and [docs/BUILD-JOURNEY.md](docs/BUILD-JOURNEY.md).

Key results: eval gate caught an insecure release (red-team 50% → guardrails → 100%, quality 91.7%); Kyverno admits only signed + eval-attested images; new app live ~5 min after PR merge; LLM budget exhaustion returns 429; OpenCost node pricing matches AWS list price; Infracost shows +$158/month on a 2-node PR.
