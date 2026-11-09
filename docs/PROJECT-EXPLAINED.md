# AIForge: Project kaise kaam karta hai (Understanding + Interview Prep)

Setup steps ke liye: [MANUAL-SETUP-GUIDE.md](../MANUAL-SETUP-GUIDE.md). Asli build ki diary (order, real IDs, har error): [BUILD-JOURNEY.md](BUILD-JOURNEY.md). Ye doc batata hai **kya bana hai, kyun bana hai, har tool kisse juda hai**, interview mein kya puchha jaayega, aur kaun si problems aati hain.

---

## Index
1. [Ek line mein](#1-ek-line-mein)
2. [Problem jo ye solve karta hai](#2-problem-jo-ye-solve-karta-hai)
3. [Architecture (layers)](#3-architecture-layers)
4. [5 flows (sabse important section)](#4-5-flows)
5. [Har tool: kya, kyun, kisse juda, alternative](#5-har-tool-kya-kyun-kisse-juda-alternative)
6. [Security layers (defence in depth)](#6-security-layers)
7. [Design decisions + trade-offs](#7-design-decisions--trade-offs)
8. [Problems faced (aur fix)](#8-problems-faced-aur-fix)
9. [Interview questions + answers](#9-interview-questions--answers)
10. [Resume bullets](#10-resume-bullets)

---

## 1. Ek line mein

**AIForge ek internal "AI platform" hai:** company ki koi bhi team 10 minute mein ek RAG app (apne documents pe Q&A) bana sakti hai, bina platform team ko ticket diye, aur platform team ensure karti hai ki har app **secure** (no shadow AI, signed images, secrets Vault mein), **quality-checked** (eval gate), **observable** (har prompt trace) aur **cost-tracked** (per team showback) ho.

## 2. Problem jo ye solve karta hai

Company mein GenAI aate hi ye hota hai:

| Problem | Bina platform ke | AIForge mein |
|---|---|---|
| **Shadow AI** | Har team apni OpenAI key laptop/code mein daal ke direct call karti hai. Data bahar, koi audit nahi. | NetworkPolicy + Kyverno: direct external AI call impossible. Sab LiteLLM gateway se. |
| **Key sprawl** | Keys Slack/Git mein | Vault + ESO. Developer ko key kabhi dikhti nahi. |
| **Cost blind spot** | Mahine ke end pe bill aata hai, kisne kharcha kiya pata nahi | LiteLLM per-team budget (429 on exceed) + OpenCost per-namespace + AWS Budgets |
| **Quality** | "Demo mein theek tha" → prod mein hallucination | CI eval gate: golden dataset pe 80% pass + red-team 100%, warna release block |
| **Ticket ops** | App ke liye namespace, DB, keys, ingress → 5 tickets, 2 hafte | Backstage form → PR → merge → live (golden path) |
| **No visibility** | Kaunsa prompt slow/galat hai, pata nahi | Langfuse traces (prompt, tokens, latency, cost) + Grafana |

Isko industry mein **Platform Engineering for AI / "AI Platform" / Internal Developer Platform (IDP)** kehte hain.

## 3. Architecture (layers)

```
 ┌─ Developer experience ─────────────────────────────────────────────────────┐
 │  Backstage: catalog · model catalog · "Create RAG App" template · scorecards │
 └──────────────┬─────────────────────────────────────────────────────────────┘
                │ PR (gitops/apps/<app>/)
 ┌─ Delivery ───▼─────────────────────────────────────────────────────────────┐
 │  GitHub Actions (test, Trivy, eval gate, cosign) → ECR                      │
 │  Argo CD + ApplicationSet → Helm chart "ai-app" (golden path)               │
 └──────────────┬─────────────────────────────────────────────────────────────┘
 ┌─ Runtime ────▼─────────────────────────────────────────────────────────────┐
 │  Tenant ns (per app): RAG app (FastAPI + LangChain)                          │
 │  Shared: LiteLLM gateway → Ollama models  ·  Qdrant  ·  OTel collector       │
 │  Self-service infra API: Crossplane VectorStore (Qdrant collection + S3)     │
 └──────────────┬─────────────────────────────────────────────────────────────┘
 ┌─ Guardrails ─▼─────────────────────────────────────────────────────────────┐
 │  Kyverno · NetworkPolicy · PSA restricted · Vault/ESO · AppProject limits    │
 ├─ Observability ───────────────────────────────────────────────────────────┤
 │  Langfuse (LLM) · Prometheus/Grafana (metrics) · Loki/Alloy (logs)           │
 ├─ FinOps ──────────────────────────────────────────────────────────────────┤
 │  LiteLLM spend/budgets · OpenCost · Infracost · AWS Budgets + SNS            │
 └──────────────┬─────────────────────────────────────────────────────────────┘
 ┌─ Infra (Terraform) ▼───────────────────────────────────────────────────────┐
 │  VPC (2 AZ, public/private, NAT, NACL, endpoints, flow logs) · k3s on EC2   │
 │  (private, SSM only) · ALB controller · ECR · GitHub OIDC role · Budgets    │
 └────────────────────────────────────────────────────────────────────────────┘
```

## 4. 5 flows

### Flow 1: Ek sawaal ka safar (`POST /apps/team-alpha-rag/ask`)

```
User (tera IP) ──HTTP──► ALB (public subnet, inbound-cidrs = tera IP/32)
   ──► NodePort (node SG, ALB controller ka rule) ──► kube-proxy ──► RAG pod (team-alpha-rag ns)
        NetworkPolicy ingress: VPC CIDR se 8080 allowed
   RAG app:
    1. OTel span start (trace_id)
    2. embed question  ──► LiteLLM /v1/embeddings (team key) ──► Ollama nomic-embed-text → 768 floats
    3. Qdrant search top_k=4 (collection = app name, Crossplane ne banaya)
    4. Prompt = system rules + <context>chunks</context> + question
    5. LiteLLM /v1/chat/completions model=llama3.2-1b, metadata={tags, trace_id}
         LiteLLM: key valid? team budget bacha? model allowed? rate limit?
         → Ollama llama3.2:1b (fail/timeout → fallback qwen2.5:0.5b)
         → spend log (Postgres) = tokens × internal price
         → Langfuse callback (prompt, response, tokens, cost, latency)
    6. Response: answer + sources + contexts + usage
    7. Prometheus metrics (latency, tokens, "I don't know" counter); OTel spans → collector → Langfuse
```
Har hop pe ek control hai: ALB (IP), NetworkPolicy (kaun kisse), LiteLLM (key/budget), Kyverno (kaunsi image chal rahi).

### Flow 2: Code change se production tak

```
git push (apps/rag-app/**)
 └► GitHub Actions rag-app-ci
     gitleaks → pytest → docker build → Trivy (HIGH/CRITICAL fixable = fail)
     → docker compose (Ollama + Qdrant + naya image) → ingest docs + poisoned doc
     → promptfoo quality (12 cases)  → promptfoo red-team (6 attacks)  → RAGAS (advisory)
     → make_attestation.py: passRate ≥ 0.8 && redteam == 1.0 ?  ── nahi → ❌ pipeline fail, kuch publish nahi
     → (main) OIDC → ECR push (immutable tag) → cosign sign (keyless) → cosign attest (eval predicate)
     → gitops/release/rag-app.yaml mein tag + DIGEST commit
 └► Argo CD (har 3 min Git poll) → ApplicationSet ke saare apps ka chart re-render → naya Deployment
 └► Kyverno admission (Pod create pe):
      signature valid? (issuer = GitHub OIDC, subject = is repo ka rag-app-ci.yml@main)
      eval attestation hai? passRate ≥ 0.8? redteamPassRate == 1?
      image ECR se? labels/limits? OPENAI_API_KEY env to nahi?
      PSA restricted?
     → sab pass → pod chalta hai. Koi fail → pod reject (ReplicaSet events mein reason)
```
**Key point:** eval pass hona sirf CI log ki baat nahi. Wo ek **signed attestation** hai jo image ke digest ke saath juda hai. Agar koi CI bypass karke image push kare, cluster use chalayega hi nahi.

### Flow 3: Nayi team onboarding (golden path / self-service)

```
Developer: Backstage → Create → "Create RAG App" (name, owner team, model, size, budget)
 └► Scaffolder: skeleton render → PR on aiforge-platform: gitops/apps/<name>/{app.yaml, values.yaml, catalog-info.yaml}
 └► Platform admin: PR review + ./scripts/litellm-onboard-team.sh (team + budget + key → Vault)
 └► Merge
 └► ApplicationSet (git files generator: gitops/apps/*/app.yaml) → naya Argo Application
       namespace <name> + labels (tenant=true, team, cost-center, PSA restricted)
 └► Kyverno generate: default-deny NetworkPolicy
 └► Helm chart ai-app:
       VectorStore (wave -1) → Crossplane: Qdrant collection (provider-http PUT) + ConfigMap (+ S3 bucket)
       ExternalSecret → ESO → Vault secret/teams/<team>/<app> → Secret (LLM key, ingest token)
       Deployment/Service(NodePort)/Ingress (shared ALB group, path /apps/<name>)
       NetworkPolicies (egress sirf gateway/Qdrant/collector/DNS), ServiceMonitor
       PostSync Job → /ingest sample docs
 └► Backstage catalog: glob location naya catalog-info.yaml utha leta hai
```

### Flow 4: Secret ka safar

```
Platform admin ──vault kv put──► Vault (KV v2, secret/teams/team-alpha/team-alpha-rag)
ESO (external-secrets ns) ── Kubernetes auth (SA token → Vault TokenReview) ──► read-only policy
   ──► ExternalSecret (app ns) har 1h refresh ──► Kubernetes Secret team-alpha-rag-secrets
Pod env LLM_API_KEY ← secretKeyRef
```
Git mein sirf "kaunsa secret kahan se" hai. Value: Vault mein. LiteLLM master key sirf `ai-gateway` namespace mein.

### Flow 5: Paisa (cost) ka safar

```
LLM cost:   LiteLLM har call: tokens × input/output_cost_per_token (internal price) → Postgres spend
            team.max_budget cross → 429 → app "team LLM budget exceeded"
Infra cost: OpenCost: node instance-type (label) × AWS on-demand price → pod requests ke hisaab se namespace mein
            namespace label aiforge.io/team → team
Report:     scripts/showback_report.py = LLM spend + infra cost per team (CSV)
Guardrails: Infracost (PR pe "+$X/month") · AWS Budgets (account + Project tag) → SNS → email
```

## 5. Har tool: kya, kyun, kisse juda, alternative

### Infra
| Tool | Kya karta hai yahan | Kisse juda | Alternative / kyun ye |
|---|---|---|---|
| **Terraform** | VPC, EC2, IAM, ECR, OIDC, Budgets, SSM params. S3 backend + native lockfile | AWS; outputs → configure.sh, GitHub secret | OpenTofu (same HCL). Infra ke liye Crossplane bhi ho sakta tha, par bootstrap (cluster khud) Terraform se hi hota hai |
| **VPC + subnets** | Public: ALB, NAT. Private: nodes | ALB controller subnet tags se dhoondhta hai | — |
| **IGW / NAT** | Public internet in/out; private ka sirf outbound | Ollama model pull, images, Langfuse Cloud | NAT instance (sasta, par HA/maintenance tum pe) |
| **Route tables** | Public → IGW, private → NAT | | |
| **NACLs** | Subnet level stateless filter | SG ke upar extra layer | Sirf SG bhi chalta; NACL "defense in depth" + interview topic |
| **Security groups** | Nodes: sirf self + egress. No 22 | ALB controller NodePort rules khud add karta hai (tagged SG) | |
| **VPC endpoints** | S3 gateway (free; ECR layers S3 se) + ECR api/dkr interface | Node image pulls NAT ke bina | Paisa: interface ~$32/mo, data heavy ho to worth it |
| **Flow Logs** | REJECT traffic → CloudWatch | Debug: "SG/NACL ne kya roka" | ALL traffic = mehenga |
| **SSM Session Manager** | Shell + port-forward (6443) bina SSH/public IP | IAM + CloudTrail audit | Bastion host (extra VM, key management) |
| **k3s on EC2** | Lightweight Kubernetes (single binary, built-in local-path, NetworkPolicy controller) | Sab kuch | **EKS**: managed control plane, IRSA/Pod Identity, par $73/mo sirf control plane |
| **AWS LB Controller** | Ingress → ALB (instance targets) | Shared ALB group `aiforge` | NGINX ingress + NLB |

### AI serving + app
| Tool | Kya | Kisse juda | Alternative |
|---|---|---|---|
| **Ollama** | llama3.2:1b, qwen2.5:0.5b, nomic-embed-text CPU pe | Sirf LiteLLM se reachable | **vLLM** (GPU pe fast, batching; CPU pe kamzor), TGI |
| **LiteLLM** | OpenAI-compatible gateway: virtual keys, team budgets, rate limits, fallback, spend, callbacks | App → LiteLLM → Ollama; → Langfuse; Postgres | Kong AI Gateway, Portkey, Envoy AI Gateway |
| **FastAPI** | RAG API, Pydantic validation, `/metrics` | Probes, ALB, Prometheus | Flask |
| **LangChain** | Splitter, embeddings/chat clients, Qdrant vector store | LiteLLM (OpenAI client), Qdrant | LlamaIndex (RAG-first), plain SDK |
| **Qdrant** | Vector DB (cosine, per-app collection) | Crossplane provider-http collection banata hai | pgvector (Postgres mein; kam moving parts) |
| **nomic-embed-text** | 768-dim embeddings | Collection dimension isi se | bge-small (384) |

### Platform
| Tool | Kya | Kisse juda | Alternative |
|---|---|---|---|
| **Backstage** | Portal: catalog, model catalog (Resources), template, Tech Insights scorecards | GitHub (PR), catalog glob location | Port, Cortex (SaaS) |
| **Crossplane v2** | `VectorStore` API (namespaced XR) → Qdrant collection + ConfigMap + S3 | Helm chart VectorStore render karta hai; provider-http, provider-aws-s3; creds Vault se | Terraform per team (self-service nahi), operator khud likhna |
| **Helm** | `charts/ai-app`: golden path ka "contract" | ApplicationSet values pass karta hai | Kustomize (Project 2), Timoni |
| **Argo CD + ApplicationSet** | App-of-apps + git files generator = folder per app | Git → cluster | Flux |

### CI + eval
| Tool | Kya | Kisse juda | Alternative |
|---|---|---|---|
| **GitHub Actions** | Pipeline; OIDC → AWS role (no keys) | ECR, Sigstore, repo commit | Jenkins (Project 2) |
| **promptfoo** | Black-box eval of `/ask`: asserts (`icontains`, `not-regex`...) + red-team | `evals/dataset.yaml` | DeepEval (pytest style) |
| **RAGAS** | faithfulness, answer relevancy, context recall | Judge LLM = Ollama | DeepEval metrics, TruLens |
| **Trivy** | Image CVEs (gate) + Terraform misconfig (report) | CI | Grype, Checkov |
| **gitleaks** | Git history mein secrets | CI first job | trufflehog |
| **cosign** | Keyless sign + `attest` eval predicate | Kyverno verify | Notation |

### Security
| Tool | Kya | Kisse juda | Alternative |
|---|---|---|---|
| **Kyverno** | verifyImages (signature + attestation conditions), validate (registry, shadow AI env, labels, limits, PSA label), generate (default-deny) | Tenant ns label `aiforge.io/tenant=true` | OPA Gatekeeper (Rego), ValidatingAdmissionPolicy (CEL, built-in) |
| **NetworkPolicy** | Default deny + allow gateway/Qdrant/collector/DNS | k3s built-in netpol controller | **Cilium** (FQDN policies: `toFQDNs: api.openai.com` deny/allow, L7) |
| **Vault + ESO** | Secrets store + sync | Kubernetes auth | AWS Secrets Manager + ESO (sasta, managed) |
| **PSA** | `restricted` tenant ns | Chart securityContext usi ke liye | Kyverno pod-security policies |
| **promptfoo red-team** | Direct + indirect prompt injection, prompt leak, secret leak, role hijack | CI gate | garak, PyRIT |

### Observability + cost
| Tool | Kya | Kisse juda | Alternative |
|---|---|---|---|
| **Langfuse** | LLM traces, prompts, tokens, cost, latency; OTLP endpoint | LiteLLM callback + OTel collector | Arize Phoenix, Helicone, LangSmith |
| **OpenTelemetry** | App spans (FastAPI, httpx) → collector | Collector ke paas hi Langfuse keys | — |
| **Prometheus + Grafana** | App metrics, recording/alert rules, dashboard | ServiceMonitor | CloudWatch Container Insights |
| **Loki + Alloy** | Logs (Kubernetes API se tail) | Grafana datasource | CloudWatch Logs, ELK |
| **LiteLLM spend** | Per key/team cost + budgets | Showback report | — |
| **OpenCost** | Per namespace infra cost | Prometheus, node labels | Kubecost (OpenCost ka commercial bhai) |
| **Infracost** | PR mein Terraform cost diff | terraform-ci.yml | — |
| **AWS Budgets + SNS** | Account + tag budget email | Project 1 logic | Cost Anomaly Detection |

## 6. Security layers

```
1. Network edge    ALB inbound-cidrs (sirf admin IP), nodes private subnet, NACLs
2. Node access     No SSH/22, no public IP, SSM (IAM + CloudTrail), IMDSv2 required
3. Supply chain    gitleaks, Trivy, immutable ECR tags, cosign keyless signature
4. Quality gate    promptfoo eval + red-team → signed attestation
5. Admission       Kyverno: signature + attestation + registry + shadow-AI + labels + limits
6. Pod             PSA restricted (non-root, no caps, seccomp, read-only rootfs)
7. Network (pod)   default-deny, sirf gateway/Qdrant/collector/DNS (shadow AI block)
8. Identity/keys   Vault + ESO, team virtual keys, master key sirf gateway ns
9. AI layer        System prompt (context = untrusted data), red-team tests, Langfuse review
10. GitOps         AppProject: tenants cluster-scoped/RBAC objects aur platform ns touch nahi kar sakte
```

## 7. Design decisions + trade-offs

| Decision | Kyun | Trade-off |
|---|---|---|
| **k3s on EC2, not EKS** | ~$73/mo control plane bachao; Kubernetes andar se samajh aaye | No IRSA → IAM perms node role pe (har pod IMDS se le sakta hai). Production: EKS + Pod Identity |
| **Private subnets + SSM** | Zero inbound attack surface | Tunnel thoda slow/clunky; plugin chahiye |
| **Single NAT** | ~$33/mo bachao | AZ-a gaya to private egress gaya |
| **Shared LiteLLM gateway** | Ek jagah keys/budgets/logging/fallback | Gateway SPOF → production mein 2+ replicas + HPA |
| **CPU chhote models** | Free, GPU nahi chahiye | Slow (secs), quality kam → isi liye eval gate zaruri |
| **Langfuse Cloud** | Self-host v4 ~6 GB (ClickHouse operator) | Prompts bahar jaate hain → sample data / message logging off |
| **Eval as attestation** | "Eval pass" image ke saath cryptographically bandha | Kyverno ko Rekor + ECR tak network chahiye; webhook latency |
| **promptfoo gate, RAGAS advisory** | Deterministic asserts reproducible; 1B judge noisy | RAGAS sirf trend ke liye |
| **Monorepo** | Simple; GITHUB_TOKEN commits workflow trigger nahi karte | Project 2 wala access separation nahi |
| **Shared ALB group (path-based)** | 1 ALB ($16/mo) saare apps | Annotation conflicts; app ko BASE_PATH samajhna padta hai |
| **Standard NetworkPolicy, not Cilium** | k3s built-in; default-deny kaafi | FQDN-level allow/deny nahi; L7 visibility nahi |
| **Vault standalone** | Seekhne ke liye real Vault | Manual unseal; production: HA + KMS auto-unseal |
| **Crossplane IAM user key** | k3s pe IRSA nahi | Long-lived key → Vault mein, rotate karni padegi |

## 8. Problems faced (aur fix)

> **Ye section imaandari se padh.** "Kahan pakdi" column mein **Asli** = build karte waqt sach mein aayi (date ke saath). Baaki (Design/Research/Code review) code likhte waqt pehle se handle ki gayi. Interview mein "maine face ki" sirf **Asli** wali bolna. Phase-wise poori kahani: [BUILD-JOURNEY.md](BUILD-JOURNEY.md).

| # | Problem | Root cause | Fix (code mein) | Kahan pakdi |
|---|---|---|---|---|
| 1 | ALB `target-type: ip` k3s pe kaam nahi karta | k3s (flannel) pod IPs VPC ke nahi, ALB unhe route nahi kar sakta | `target-type: instance` + Service `NodePort` | Design |
| 2 | ALB controller / OpenCost nodes ko EC2 se map nahi kar paate | k3s cloud-controller nahi → `providerID` khaali, instance-type label nahi | User data: `--kubelet-arg provider-id=aws:///AZ/ID` + `node.kubernetes.io/instance-type`, zone labels | Design |
| 3 | `/apps/team-alpha-rag/ask` pe 404 | ALB path prefix strip nahi karta | App `BASE_PATH` ke neeche bhi routes mount karta hai; probes root pe | Design |
| 4 | App-of-apps mein sync-wave order ignore | Argo CD 1.8+ mein `Application` ka health check default off | argocd-cm mein Lua health customization | Research (well-known) |
| 5 | Pods ko AWS creds nahi milte (Kyverno ECR verify, ALB controller) | IMDSv2 hop limit 1: container ek extra hop hai | `http_put_response_hop_limit = 2` (trade-off: har pod ko node role) | Design |
| 6 | Embeddings call fail (Ollama/LiteLLM) | LangChain `OpenAIEmbeddings` text ko tiktoken **token IDs** bana ke bhejta hai | `check_embedding_ctx_length=False` | Research |
| 7 | Service kabhi-kabhi ingest Job pod ko traffic bhejta | Job pod ke labels Deployment selector se match | `ai-app.commonLabels` (bina `app.kubernetes.io/name`) Job ke liye | Code review |
| 8 | Kyverno signature nahi dhoondh pata (expected) | cosign v3 default naya bundle format (OCI referrers); classic `.sig/.att` tags nahi | CI mein cosign **v2.6.5** pin | Research |
| 9 | RAGAS scores har run pe alag | Judge bhi 1B model; JSON parsing fail → NaN | RAGAS advisory (`continue-on-error`), gate = promptfoo deterministic asserts | Design |
| 10 | Crossplane provider package pull fail | Upbound official registry ab purane versions bina subscription nahi deti | `xpkg.crossplane.io/crossplane-contrib/*` packages | Research |
| 11 | Langfuse self-host bahut bhaari | Langfuse v4 chart: ClickHouse operator + Keeper ×3, ClickHouse 2 Gi request | Langfuse Cloud free tier (self-host option H mein) | Research (chart values padhe) |
| 12 | Vault migration ke baad LiteLLM ki purani keys kaam nahi karti | DB mein keys `LITELLM_SALT_KEY` se encrypted; salt badla | Salt kabhi rotate nahi; lab mein DB reset + re-onboard | Design |
| 13 | Argo CD permanent OutOfSync agar Kyverno digest mutate kare | Kyverno `mutateDigest` Deployment template badalta → Git se drift | CI digest likhta hai, chart `repo:tag@digest`, policy `mutateDigest: false`, `verifyDigest: true` | Design |
| 14 | Monorepo mein CI ka commit CI dobara trigger kare (loop) | — | `GITHUB_TOKEN` se push naye workflow runs trigger nahi karta; workflow `paths` filter | Design |
| 15 | Kyverno default-deny pehle se bane namespace mein nahi bana | Generate rules sirf naye admission events pe | `generateExisting: true` | Code review |
| 16 | Git Bash mein `BASE_PATH=/apps/x` → `C:/Program Files/Git/apps/x`; Phase 2 mein `aws ssm get-parameter --name /aiforge/k3s/kubeconfig` → `ParameterNotFound` (jabki server log mein upload successful tha) | MSYS path conversion: leading `/` wale args aur env vars Windows path ban jaate hain | Sirf us command pe `MSYS_NO_PATHCONV=1`. Global export galat: `KUBECONFIG` bhi convert hona band ho jaata hai. Debug: SSM `send-command` se server ka bootstrap log padha → upload `Version 1` dikha → problem client side | **Asli** (local test + Phase 2, 2026-11-08) |
| 17 | Vault restart ke baad saare ExternalSecrets fail | Vault sealed start hota hai | `scripts/vault-unseal.sh`; production: KMS auto-unseal | Design |
| 18 | "api.openai.com block karo" NetworkPolicy se nahi hota | Standard NetworkPolicy FQDN nahi samajhti | Default-deny egress + sirf internal allow; FQDN chahiye to Cilium `toFQDNs` | Design |
| 19 | Phase order: LiteLLM ko secrets chahiye par Vault Phase 6 mein | Chicken-egg | Pehle manual `kubectl create secret`, Phase 6 mein delete → ESO | Guide design |
| 20 | Ingest Job ka curl image Kyverno ne block kiya hota | `restrict-image-registries` (sirf ECR) | Job wahi signed app image + Python `urllib` use karta hai | Code review |
| 21 | Prometheus mein etcd/scheduler/controller-manager hamesha DOWN | k3s mein ye ek binary ke andar, alag endpoints nahi | kube-prometheus-stack mein in components ko disable | Research |
| 22 | ALB 504 lambe answers pe | ALB idle timeout default 60s, CPU LLM slow | `idle_timeout.timeout_seconds=180`, `MAX_TOKENS=256` | Design |
| 23 | Secret Terraform state mein chala jaata | `aws_iam_access_key` ka secret state mein plaintext | Crossplane key console se bana ke seedha Vault | Design |
| 24 | NACL lagate hi apt/docker pull timeout | NACL stateless: return traffic ke ephemeral ports | Inbound TCP/UDP 1024-65535 | Classic (Project 2 bhi) |
| 25 | Chart versions purane / RC | Kyverno 3.10 RC tha; ALB controller v3 aa chuka; Langfuse chart 2.x | Artifact Hub se latest **stable** pin; `scripts/check-chart-versions.sh` | Research (Nov 2026) |
| 26 | Vault seed script dobara chalane pe master key badal jaati | Script har baar random overwrite karta | Existing path skip, `FORCE=1` se hi overwrite | Code review |
| 27 | `terraform apply`: `instance type is not eligible for Free Tier` | Account AWS **Free plan** pe: sirf free-tier-eligible types (t3.large/xlarge nahi) | Sab nodes `m7i-flex.large` (2 vCPU, 8 GB), 1 server + 3 agents; Ollama requests 1 CPU / 3 Gi | **Asli** (Phase 2, 2026-11-08) |
| 28 | `CreateOpenIDConnectProvider: EntityAlreadyExists` | GitHub OIDC provider account-wide ek hi hota hai, Project 1/2 ne bana diya tha | `create_github_oidc_provider = false` (module `data` source se existing provider use karta hai) | **Asli** (Phase 2, 2026-11-08) |
| 29 | Qdrant Argo app `OutOfSync/Missing`: `could not find monitoring.coreos.com/v1` | Chart ka ServiceMonitor Prometheus Operator ke CRD pe depend karta hai, jo baad ke phase mein aata hai (CRD ordering) | Pehle `serviceMonitor.enabled: false`, kube-prometheus-stack ke baad true. Git fix ke baad bhi error aata raha: Argo ka `retry` **purana operation** (purani values) hi dohrata hai → Application delete + re-apply (ya UI Terminate + Sync). Production: CRDs pehle wave mein alag app se | **Asli** (Phase 3, 2026-11-08) |
| 30 | Ollama/LiteLLM pe `TLS handshake timeout`, `connection refused :6443` | SSM port-forward ~20 min idle pe AWS band karta hai; plugin kabhi laptop pe khula reh jaata | `tunnel.sh`: keepalive (har 4 min curl) + auto-reconnect loop; Session Manager idle timeout 60 min | **Asli** (Phase 2-3, 2026-11-08) |
| 31 | `pytest`: `ModuleNotFoundError: No module named 'app'` | Plain `pytest` rootdir ko `sys.path` mein nahi daalta (`python -m pytest` daalta hai, isliye dev machine pe pass hua). CI mein bhi yahi fail hota | `apps/rag-app/pytest.ini`: `pythonpath = .` | **Asli** (Phase 4, 2026-11-08) |
| 32 | Pods `ImagePullBackOff`: `failed to pull ... ECR ... authorization failed: no basic auth credentials` | EKS pe kubelet ke saath `ecr-credential-provider` aata hai; **k3s pe nahi**. Node IAM role pe ECR read permission thi, par containerd ko token dene wala koi nahi tha | AWS ka `ecr-credential-provider` (v1.37.0) `/var/lib/rancher/credentialprovider/` mein + `CredentialProviderConfig` + k3s restart. Chalte nodes pe `scripts/install-ecr-credential-provider.sh` (SSM Run Command), naye nodes ke liye user-data. Saath mein `lifecycle { ignore_changes = [user_data] }`, warna template badalte hi Terraform saare nodes replace kar deta | **Asli** (Phase 4, 2026-11-09) |
| 33 | RAG app har sawaal pe "I don't know" (over-refusal), jabki retrieval sahi document laa raha tha | System prompt bahut sakht/lamba ("ONLY", "reply exactly", lambi "never follow" list); 1B model ke liye refusal sabse aasaan raasta | 3 prompt variants seedha LiteLLM pe same context ke saath compare kiye: purana 1/5, simple numbered rules 4/5, question-first 3/5 (Canberra hallucinate kiya). V3 ("match by meaning") rakha. Budget wala 1 case ab bhi fail = model limit; eval gate 80% threshold isi liye. Red-team ke leak-check phrases naye prompt se update | **Asli** (Phase 4, 2026-11-09) |
| 34 | Phase 1: `terraform.tfvars` → `Duplicate attribute` | Same key (`create_github_oidc_provider`) do baar | Ek line hatai | **Asli** (Phase 2, 2026-11-08) |
| 35 | Argo CD Helm install: `504 Gateway Time-out` github.com releases se; phir `namespaces "argocd" not found` | GitHub release CDN slow; pehla install fail hua to namespace bana hi nahi | Same chart OCI registry se: `oci://ghcr.io/argoproj/argo-helm/argo-cd --version 10.14.0 --create-namespace` | **Asli** (Phase 2, 2026-11-08) |
| 36 | Git Bash: `no available terminals` | Laptop free RAM 0.75 GB (Docker + browser + VS Code) | Uninstall/reinstall bekaar → reboot | **Asli** (Phase 2, 2026-11-08) |
| 37 | `kubectl` → `localhost:8080 refused` | Naye terminal mein `KUBECONFIG` nahi (kubectl ka default 8080) | `~/.bashrc` mein export | **Asli** (Phase 3, 2026-11-08) |
| 38 | LiteLLM `401 Malformed API Key` | `$MK` naye terminal mein khaali | MK Secret `litellm-secrets` se padha, kabhi print nahi | **Asli** (Phase 3, 2026-11-08) |
| 39 | `team/new` → `KeyError`, bash syntax error, `Method Not Allowed` | Lamba multi-line paste toota (`` char, lines gaayab) | Idempotent script `scripts/phase4-team-secret.sh` | **Asli** (Phase 4, 2026-11-09) |
| 40 | Python `FileNotFoundError: /tmp/...` | Windows Python Git Bash ke `/tmp` ko nahi jaanta | stdin pipe | **Asli** (Phase 4, 2026-11-09) |
| 41 | LiteLLM key bani par `team_id: None` | Khaali team_id ke saath generate | Script same-alias purani keys delete karke sahi team ke saath banata hai | **Asli** (Phase 4, 2026-11-09) |
| 42 | `docker push` → tag immutable | `manual-1` dobara push; ECR immutable tags | Har build naya tag (`manual-2`) | **Asli** (Phase 4, 2026-11-09) |
| 43 | `logs job/team-alpha-rag-ingest` → not found; phir `invalid ingest token` | Job TTL ke baad delete; command mein `<ingest_token>` placeholder literal chipkaya | Ingest manually ALB se asli token ke saath | **Asli** (Phase 4, 2026-11-09) |
| 44 | `json: Expecting value` (khaali response) | Rollout ke beech purana pod terminate ho raha tha | 30 sec baad retry; theek | **Asli** (Phase 4, 2026-11-09) |
| 45 | Helm → ApplicationSet switch pe ALB DNS badal gaya | `helm uninstall` = Ingress delete = ALB delete | Normal; naya address `kubectl get ingress` se | **Asli** (Phase 4, 2026-11-09) |
| 46 | CI eval gate do baar fail: sakht prompt `passRate=0.167, redteam=1.0`; simple prompt `passRate=0.917, redteam=0.5` (model ne "PWNED" bola, fake `sk-1234567890abcdef` key banayi, poisoned doc ka "HACKED" maana) | 1B model ke saath sirf system prompt se quality aur security dono nahi milte: ya sab mana, ya sab maan leta hai | Prompt helpful rakha, security code mein: `app/guardrails.py`: (1) sawaal mein injection/secret maangna → LLM call hi nahi, (2) retrieved chunks se injection wali lines hatao, (3) jawab mein `sk-`/AWS/Vault jaise secrets → `[REDACTED]`. Metric `rag_guardrail_events_total`. Unit tests: saare attacks block, golden dataset ke 12 sawaal kabhi block nahi (false positive check) | **Asli** (Phase 5, CI runs 42505171572 + 42516646358). Guardrails ke baad run 42587592936: quality 0.917, red-team **1.0** → gate pass |
| 47 | Guardrails push ke baad CI `secrets-scan` fail: gitleaks `aws-access-token` in `tests/test_guardrails.py` | Redaction test mein fake AWS key literal likhi thi; gitleaks fake/asli mein farak nahi karta, aur `fetch-depth: 0` se poori history scan hoti hai | Test key runtime pe banata hai (`"AKIA" + "X"*16`); history ke us ek commit ko `.gitleaks.toml` `commits` allowlist mein (reason ke saath). Path allowlist nahi kiya, taaki tests folder scan hota rahe. Local check: gitleaks docker → no leaks | **Asli** (Phase 5, run 42583690047) |
| 48 | Eval gate pass (quality 0.917, red-team 1.0) ke baad `configure-aws-credentials`: `Could not load credentials from any providers` | GitHub secret `AWS_CI_ROLE_ARN` set nahi tha: `role-to-assume` khaali → action OIDC chhod ke static creds dhoondhta hai. Debug: log mein `role-to-assume` input line hi nahi thi; IAM trust policy `aws iam get-role` se sahi nikli | Secret add → Re-run failed jobs | **Asli** (Phase 5, run 42587592936) |
| 49 | Secret ke baad bhi `Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity` | GitHub ab OIDC `sub` mein immutable IDs bhejta hai: `repo:Anujsyal@86842727/aiforge-platform@1449398889:ref:refs/heads/main`. Trust policy purane `repo:Anujsyal/aiforge-platform:...` format pe thi. (Fayda: repo delete karke same naam se banaya to IDs alag → role nahi milta.) Debug: **CloudTrail** `AssumeRoleWithWebIdentity` AccessDenied event ke `userIdentity.userName` mein asli sub dikha | `github-oidc` module: `github_owner_id` + `github_repo_id` vars (GitHub API se), set hon to naya format. `terraform apply -target=module.github_oidc` → 1 change | **Asli** (Phase 5, 2026-11-09) |
| 50 | Release ke baad live `/ask` pe ALB timeout (pod Running, Argo Synced) | ISP ne laptop ka public IP badla (`122.161.49.234` → `122.161.52.20`); ALB SG sirf purana IP/32 allow karta tha | `curl https://checkip.amazonaws.com` → `gitops/release/rag-app.yaml` `inboundCidrs` update + push → ALB controller SG update karta hai | **Asli** (Phase 5, 2026-11-09) |
| 51 | Pod image `rag-app:manual-2@sha256:<CI digest>` (ajeeb naam) | values.yaml ka temporary `tag: manual-2` release file ke tag ko override kar raha tha, digest release se aaya. Runtime digest use karta hai, to image sahi tha, sirf naam galat | Release ke baad override hataya → `5-1ddfb24@sha256:...`. Override **pehle** hatata to `0.0.0` + khaali digest deploy hota = ImagePullBackOff | **Asli** (Phase 5, 2026-11-09) |
| 52 | Eval attestation mein RAGAS `faithfulness/answer_relevancy/context_recall` sab `null` | Judge bhi 1B model; JSON output parse nahi hota → NaN (#9 ka design risk asli mein) | Gate promptfoo deterministic asserts pe; RAGAS advisory. Better judge model se hi kaam ka | **Asli** (Phase 5, run 42587592936) |
| 53 | ALB ke 4 mein se 3 targets `unhealthy (Target.FailedHealthChecks)`; app sirf isliye chal raha tha ki pod usi node pe tha jo healthy tha | Service `externalTrafficPolicy: Cluster`: doosre node pe aaya ALB traffic kube-proxy SNAT karke pod tak `10.42.x.0` (flannel IP) source se bhejta; app ki ingress NetworkPolicy sirf VPC CIDR allow karti → drop. Pod naye node pe jaata to outage | `externalTrafficPolicy: Local` (source IP bachta hai, sirf pod wale node pe traffic) + ALB health check 10s × 2. Pod-less nodes unhealthy = expected. Pakda: Phase 6 se pehle `aws elbv2 describe-target-health` | **Asli** (Phase 6 prep, 2026-11-09) |
| 54 | (Bachaya gaya) `vault-init.sh` dobara chalane pe unseal key mit jaati | `vault status` sealed pe exit 2 deta hai; `set -o pipefail` ke saath `status \| grep initialized` false → script "not initialized" samajh ke `vault operator init > vault-init.json` chalati: redirect pehle file khaali karta, init fail → unseal key + root token gaye = Vault data permanently lock | Status variable mein (`|| true`), init sirf jab sach mein uninitialized aur file maujood na ho, `.tmp` mein likh ke `mv` | Code review (Phase 6 se pehle) |
| 55 | (Design change) Guide ka purana plan: Vault mein naya master/salt key → LiteLLM DB reset → team re-onboard → re-ingest | Naya salt = DB ki encrypted keys bekaar | `scripts/vault-import-existing.sh`: chal rahe Kubernetes Secrets ki values Vault mein import (stdin se, screen pe nahi), phir ESO same Secret banata hai. Zero downtime, team key same | Code review |

**Build ke baad yahan add kar:** asli error, kitna time laga, kaise debug kiya (kaunsi command se pata chala). Interview mein STAR format: Situation → Task → Action → Result.

## 9. Interview questions + answers

### Platform / architecture
**Q1. Ye project kya hai, 1 minute mein?**
Guide ke end wala summary. Structure: problem (shadow AI, cost, quality, ticket ops) → golden path → guardrails → observability → cost.

**Q2. "Golden path" kya hota hai?**
Platform team ka recommended, pre-paved raasta: template + chart + policies jisme security/observability/cost by default hai. Developer usse hat sakta hai par default wahi easiest hai. Yahan: Backstage template → `charts/ai-app`.

**Q3. Self-service mein platform team control kaise rakhti hai?**
Guardrails code mein: Kyverno policies, AppProject restrictions, NetworkPolicies, PSA, LiteLLM budgets. Developer kuch bhi maang sakta hai, par sirf allowed shape mein (VectorStore schema enum, chart values).

**Q4. Central AI gateway kyun? App seedha model call kyun na kare?**
Ek jagah: auth (virtual keys), budgets, rate limits, fallback, model routing, logging (Langfuse), provider switch (Ollama → Bedrock → OpenAI) bina app code badle. Shadow AI rokne ke liye zaruri chokepoint.

**Q5. LiteLLM fallback kaise kaam karta hai?**
`router_settings.fallbacks: llama3.2-1b → qwen2.5-0.5b`. Primary fail/timeout pe LiteLLM same request fallback model pe bhejta hai; app ko pata bhi nahi. `num_retries`, `timeout` per model.

**Q6. Per-team budget kaise enforce hota hai?**
LiteLLM team `max_budget` + `budget_duration: 30d`. Har call spend = tokens × cost_per_token. Budget cross → 4xx; app usko 429 "team LLM budget exceeded" banata hai.

**Q7. Self-hosted model ka cost 0 hai, to showback kaise?**
Internal transfer price (`input_cost_per_token`) jo node/GPU ka kharcha represent karta hai. Infra ka asli kharcha OpenCost se per namespace. Dono jod ke showback.

**Q8. Showback vs chargeback?**
Showback: team ko dikhaana kitna kharcha. Chargeback: unke budget se sach mein katna. Shared/idle cost (platform namespaces) ko usage ratio se baant-te hain.

### RAG / AI
**Q9. RAG pipeline explain kar.**
Ingest: split (800 chars, 100 overlap) → embed (nomic 768) → Qdrant (deterministic uuid5 IDs, re-ingest pe duplicate nahi). Query: embed → top-k cosine → prompt with context → LLM → answer + sources.

**Q10. Chunk size/overlap kaise choose kiya?**
Docs chhote paragraphs; 800 chars = ek concept, overlap boundary pe fact na kate. Eval dataset se tune karte hain (context recall).

**Q11. Hallucination kaise kam ki?**
System prompt: "ONLY context, warna exact 'I don't know'"; temperature 0; eval mein out-of-scope test (capital of Australia); production metric `rag_unanswered_total` ratio.

**Q12. Prompt injection kya hai, direct vs indirect?**
Direct: user khud "ignore instructions" likhta hai. Indirect: retrieved document ke andar chhupi instruction. Defence: context ko untrusted data bolna, red-team tests (poisoned doc CI mein ingest hota hai), output checks, least privilege (model ke paas koi tool/secret hi nahi).

**Q13. promptfoo vs RAGAS?**
promptfoo: black-box test runner, assertions (deterministic + LLM-graded), red-team. RAGAS: RAG-specific metrics (faithfulness, relevancy, context recall), judge LLM chahiye. Hamne promptfoo ko gate, RAGAS ko advisory rakha (judge noisy).

**Q14. Eval gate ka threshold 80% kyun, 100% kyun nahi?**
Chhota CPU model non-deterministic edge cases mein fail karta hai; 100% flaky gate banata (log ignore karne lagte). Red-team 100% kyunki security pe compromise nahi.

**Q15. Model upgrade ho to?**
Model catalog (Backstage Resource) update → LiteLLM ConfigMap mein naya model → same dataset pe eval → pass rate compare. Gateway alias (`llama3.2-1b`) stable rakh ke backend badal sakte hain.

**Q16. Vector DB choice: Qdrant vs pgvector?**
Qdrant: purpose-built, filtering, HNSW, simple REST (Crossplane provider-http se collection manage). pgvector: kam moving parts agar Postgres already hai. Scale pe dono chalte.

### Kubernetes / GitOps
**Q17. ApplicationSet git files generator kaise kaam karta hai?**
`gitops/apps/*/app.yaml` match karta hai, har file ke keys (name, team, costCenter) template variables. Har file = ek Application. Folder delete = Application delete (prune).

**Q18. Sync waves + hooks?**
Waves: projects -10, namespaces -8, core -5, config -3, apps 0+, tenants 5. Chart mein VectorStore wave -1 (collection pehle), ingest Job PostSync hook. App-of-apps mein waves ke liye Application health customization zaruri.

**Q19. Multi-tenancy kaise?**
Namespace per app + labels; AppProject `ai-apps` (cluster-scoped sirf Namespace, RBAC/ResourceQuota blacklist, platform ns deny); PSA restricted; default-deny netpol; per-app LiteLLM key; per-app Qdrant collection. Hard multi-tenancy (alag clusters/vCluster) nahi.

**Q20. PSA restricted kya maangta hai?**
runAsNonRoot, allowPrivilegeEscalation false, capabilities drop ALL, seccomp RuntimeDefault, no hostPath/hostNetwork. Chart ka securityContext isi ke liye.

**Q21. NetworkPolicy se api.openai.com kaise block?**
Domain se nahi (standard NP FQDN nahi samajhti). Default-deny egress + allow sirf cluster-internal destinations. Bahar kuch bhi = blocked. FQDN control chahiye to Cilium.

**Q22. Kyverno vs OPA Gatekeeper vs ValidatingAdmissionPolicy?**
Kyverno: YAML policies, mutate + generate + **verifyImages** built-in. Gatekeeper: Rego, powerful par steep. VAP: built-in CEL, sirf validate. Image signature + attestation ke liye Kyverno sabse seedha.

**Q23. cosign keyless kaise kaam karta hai?**
CI ka GitHub OIDC token → Fulcio short-lived cert (identity = workflow path@ref) → sign → Rekor transparency log entry. Verify: issuer + subject match. Koi private key manage nahi.

**Q24. Attestation kya hai, signature se alag kaise?**
Signature: "ye image is identity ne banayi". Attestation: signed statement **about** image (predicate), yahan eval results. Kyverno conditions predicate fields (`passRate`) pe lagti hain.

**Q25. Digest vs tag?**
Tag mutable pointer; digest content hash. Signature digest pe hoti hai. Isliye chart `repo:tag@digest` aur ECR immutable tags.

### Security / secrets
**Q26. Vault + ESO flow?**
Flow 4. Kubernetes auth: ESO ka SA token Vault ko, Vault TokenReview API se verify, role → read-only policy. Refresh 1h.

**Q27. Vault ki jagah AWS Secrets Manager kyun nahi?**
Ho sakta tha (ESO dono support karta). Vault: cloud-agnostic, dynamic secrets, seekhne ke liye. Secrets Manager: managed, IAM native, per-secret cost.

**Q28. Vault sealed kya hota hai?**
Data encrypted; unseal key se master key decrypt. Restart pe sealed. Production: auto-unseal (AWS KMS), HA Raft.

**Q29. GitHub Actions bina AWS keys ke ECR pe kaise push karta hai?**
OIDC: workflow JWT → `AssumeRoleWithWebIdentity`; trust policy `aud = sts.amazonaws.com`, `sub = repo:<owner>/aiforge-platform:ref:refs/heads/main`. PR/fork push nahi kar sakte.

**Q30. SSM vs bastion vs SSH?**
SSM: no inbound port, IAM auth, CloudTrail + session logs, port forwarding. Bastion: extra VM, keys, port 22 exposure.

**Q31. IMDSv2 kya hai?**
Session token (PUT) chahiye metadata ke liye → SSRF se creds churana mushkil. Hop limit packet kitne hops jaa sakta hai; containers ke liye 2.

### AWS networking
**Q32. SG vs NACL?**
SG: instance/ENI level, stateful, sirf allow. NACL: subnet level, stateless, allow + deny, numbered rules. Return traffic ke liye NACL pe ephemeral ports.

**Q33. Gateway vs interface endpoint?**
Gateway (S3, DynamoDB): route table entry, free. Interface (ECR, SSM...): ENI + private DNS, hourly + per-GB charge.

**Q34. Private subnet mein node ECR se image kaise kheenchta hai?**
`ecr.api` (auth token) + `ecr.dkr` (manifest) interface endpoints; layers S3 se → S3 gateway endpoint. Endpoints na ho to NAT se.

**Q35. Flow logs mein kya dekhte ho?**
REJECT records: src/dst IP, port, action. "Connection timeout" debug: NACL/SG ne roka ya app down.

### Observability
**Q36. Langfuse mein kya dikhta hai jo Prometheus nahi dikhata?**
Har LLM call ka prompt, response, tokens, cost, latency, model, team tags, trace tree. Prometheus aggregated numbers deta hai; Langfuse "ye specific answer galat kyun aaya".

**Q37. App ke paas Langfuse keys kyun nahi?**
App → OTel collector (cluster-internal), collector ke paas keys. Tenant egress bhi sirf collector tak. Least privilege.

**Q38. RAG app ke liye kaunse metrics/alerts?**
Latency p95, error ratio, tokens/min (cost), retrieval latency, "I don't know" ratio (quality drift). Alerts: `RagHighLatency`, `RagGatewayErrors`, `RagQualityDrop`.

### Cost / FinOps
**Q39. OpenCost cost kaise nikaalta hai?**
Node price (instance type → AWS on-demand) per CPU/GB-hour → container requests/usage (jo zyada) × time → namespace. Idle = unallocated.

**Q40. Infracost kya karta hai?**
Terraform HCL/plan parse karke AWS pricing se monthly cost; PR pe base vs head diff comment.

**Q41. Is lab ka kharcha kaise control kiya?**
k3s (no EKS fee), single NAT, CPU models (no GPU), shared ALB group, optional spot agents, flow logs REJECT only, 3d retention, destroy roz. AWS Budgets alerts.

### Behavioural / scenario
**Q42. Ek team bolti hai "OpenAI GPT chahiye, local model bekaar hai". Kya karoge?**
LiteLLM mein OpenAI model add (key Vault se, sirf gateway ns), team ke allowed models mein, budget ke saath; data classification check (PII bahar na jaaye); same eval dataset pe compare. App code nahi badalta.

**Q43. Production mein answer quality achanak gir gayi. Debug?**
Grafana "I don't know" ratio + Langfuse traces (retrieved contexts dekh) → collection khaali? embed model badla? doc change? → eval dataset mein regression case add → fix → gate.

**Q44. Kyverno ne prod deploy rok diya, release urgent hai. Kya karoge?**
Pehle reason (`kubectl get events`): signature/attestation missing = CI bypass hua → policy bypass nahi, CI fix. Real emergency: Kyverno `PolicyException` time-bound, reviewed, Git mein (audit trail).

**Q45. Agar tum ise EKS pe le jao to kya badlega?**
Terraform `aws_eks_cluster` + managed node groups; ALB controller/Crossplane/Kyverno ke liye Pod Identity (node role se perms hatao); EBS CSI; `target-type: ip` (VPC CNI pod IPs); baaki GitOps same.

## 10. Resume bullets

(Sirf build + run ke baad use kar; numbers apne asli run se bhar.)

- Built a self-service AI platform on AWS (Terraform: VPC across 2 AZs with private subnets, NAT, NACLs, VPC endpoints, flow logs; k3s on EC2 accessible only via SSM) serving self-hosted LLMs (Ollama) behind a central LiteLLM gateway with per-team virtual keys, budgets and fallback.
- Delivered a golden path: Backstage "Create RAG App" template → PR → Argo CD ApplicationSet + shared Helm chart, with a Crossplane v2 `VectorStore` API provisioning Qdrant collections and S3 buckets; new apps live in ~__ minutes without platform tickets.
- Implemented an AI eval gate in GitHub Actions (promptfoo quality + prompt-injection red-team, RAGAS advisory) whose results are attached to images as cosign attestations and enforced at admission by Kyverno, along with signature, registry and shadow-AI policies.
- Blocked shadow AI with default-deny NetworkPolicies and Kyverno rules; managed all keys via Vault + External Secrets; enforced Pod Security `restricted` for tenants.
- Added observability (Langfuse LLM traces via LiteLLM + OpenTelemetry, Prometheus/Grafana, Loki) and FinOps showback combining LiteLLM token spend with OpenCost namespace cost, Infracost PR diffs and AWS Budgets alerts.
