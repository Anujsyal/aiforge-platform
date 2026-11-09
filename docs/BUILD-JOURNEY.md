# AIForge: Build Journey (maine kya banaya, kis order mein, kya toota, kaise theek kiya)

> **Ye doc kis liye hai:** ek baar shuru se end tak padh, aur poora project samajh aa jaaye: pehle kya bana, uske upar kya bana, kaun kisse baat karta hai, aur har step pe kaunsi galti/problem aayi.
>
> - Commands step by step: [MANUAL-SETUP-GUIDE.md](../MANUAL-SETUP-GUIDE.md)
> - Har tool ki theory, interview Q&A: [PROJECT-EXPLAINED.md](PROJECT-EXPLAINED.md)
> - **Ye doc** = asli build ki diary (2026-11-07 se), real IDs, real errors.

**Status (2026-11-09):** Phase 0-4 done ✅, Phase 5 chal raha hai (~50%).

---

## Index
1. [Poori kahani 1 page mein](#1-poori-kahani-1-page-mein)
2. [Layer by layer: kya kiske upar bana](#2-layer-by-layer-kya-kiske-upar-bana)
3. [Connection map: kaun kisse, kaise baat karta hai](#3-connection-map-kaun-kisse-kaise-baat-karta-hai)
4. [Phase by phase diary](#4-phase-by-phase-diary)
5. [Roz ka kaam (operations notes)](#5-roz-ka-kaam-operations-notes)
6. [Saari galtiyan + lessons (ek list)](#6-saari-galtiyan--lessons-ek-list)
7. [Abhi ki state + temporary jugaad](#7-abhi-ki-state--temporary-jugaad)
8. [Aage kya bachaa hai (Phase 5-10)](#8-aage-kya-bachaa-hai-phase-5-10)
9. [Interview mein ye kahani kaise sunani hai](#9-interview-mein-ye-kahani-kaise-sunani-hai)

---

## 1. Poori kahani 1 page mein

Goal: ek **internal AI platform**, jahan company ki koi bhi team apne documents pe Q&A wala RAG app bana sake, aur platform team ensure kare ki wo secure, quality-checked, observable aur cost-tracked ho.

Build ka order ek ghar banane jaisa hai, neeche se upar:

```
 Phase 0  Zameen ke kagaz      → GitHub repo, placeholders, Terraform state bucket (S3)
 Phase 1  Plot + boundary wall → VPC: subnets, NAT, route tables, NACL, endpoints, flow logs
 Phase 2  Ghar ka dhancha      → 4 EC2 pe k3s (Kubernetes), SSM tunnel, ALB controller, Argo CD
 Phase 3  Bijli-paani          → Ollama (models), LiteLLM (gateway: keys, budget), Qdrant (vector DB)
 Phase 4  Pehla kiraayedaar    → RAG app (FastAPI) → ECR image → team key → ALB pe live → GitOps (ApplicationSet)
 ──────── yahan tak done ────────
 Phase 5  Quality check gate   → GitHub Actions: tests, Trivy, promptfoo eval, cosign sign
 Phase 6  Security guard       → Vault + ESO (secrets), Kyverno (sirf signed images), NetworkPolicy (no shadow AI)
 Phase 7  CCTV                 → Prometheus, Grafana, Loki, OTel, Langfuse
 Phase 8  Reception desk       → Backstage (self-service form), Crossplane (VectorStore API)
 Phase 9  Bijli ka meter       → OpenCost, Infracost, showback report
 Phase 10 Demo + cleanup
```

**Har phase pichhle pe depend karta hai.** Isiliye order badla nahi ja sakta:
- Cluster ko network chahiye (Phase 1 → 2).
- Models ko cluster chahiye (2 → 3).
- RAG app ko LLM gateway aur vector DB chahiye (3 → 4).
- CI ko chalta app chahiye, jispe eval chala sake (4 → 5).
- Kyverno ko signed images chahiye, warna wo sab block kar dega (5 → 6).

---

## 2. Layer by layer: kya kiske upar bana

```
                          ┌────────────────────── Laptop (Windows, Git Bash) ──────────────────────┐
                          │ terraform · aws cli · kubectl · helm · docker · python · git            │
                          │ tunnel.sh ──SSM──► server:6443        browser/curl ──HTTP──► ALB         │
                          └───────────┬────────────────────────────────────────┬──────────────────┘
                                      │ (no SSH, no public IP)                 │ sirf 122.161.49.234/32
 AWS ap-south-1 ──────────────────────▼────────────────────────────────────────▼──────────────────────
 │ S3 aiforge-tfstate-770803607362 (Terraform state)   ECR aiforge/rag-app   SSM Parameter Store      │
 │                                                                     (/aiforge/k3s/token, kubeconfig)│
 │ VPC aiforge 10.20.0.0/16 (vpc-090f7e7572c0ceb89)                                                   │
 │ ├─ public  10.20.0.0/24 (1a), 10.20.1.0/24 (1b): IGW route · NAT Gateway · ALB "aiforge"            │
 │ └─ private 10.20.10.0/24 (1a), 10.20.11.0/24 (1b): NAT route · S3 gateway + ECR interface endpoints │
 │      │                                                                                              │
 │      ├─ k3s server  10.20.10.10  (i-094f278871a07219f)  control plane + Argo CD + ALB controller    │
 │      ├─ agent-0  pool=ai       → Ollama (nodeSelector se yahi node)                                 │
 │      ├─ agent-1  pool=general  ┐ LiteLLM + Postgres, Qdrant, team-alpha-rag:                         │
 │      └─ agent-2  pool=general  ┘ kaunsa pod kis node pe, ye scheduler decide karta hai                │
 │         (sab m7i-flex.large: 2 vCPU, 8 GB)        │
 └─────────────────────────────────────────────────────────────────────────────────────────────────────
```

Kubernetes ke andar (namespaces):

| Namespace | Kya chal raha hai | Kisne banaya |
|---|---|---|
| `kube-system` | k3s core, CoreDNS, **AWS Load Balancer Controller** | k3s + Argo CD (app `aws-load-balancer-controller`) |
| `argocd` | Argo CD (GitOps engine) | Helm (manual, ek baar), baaki sab ye banata hai |
| `ai-serving` | Ollama | Argo CD app `ollama` |
| `ai-gateway` | LiteLLM + Postgres (spend DB) | Argo CD app `litellm` (secret manual) |
| `vector-db` | Qdrant | Argo CD app `qdrant` |
| `team-alpha-rag` | RAG app pod, Service (NodePort), Ingress, NetworkPolicy | ApplicationSet `rag-apps` → app `team-alpha-rag` |
| baaki platform ns | monitoring, security, etc. (khaali, aage ke phases ke liye) | Argo CD app `platform-namespaces` |

---

## 3. Connection map: kaun kisse, kaise baat karta hai

| Se → Tak | Kaise (protocol/port) | Auth / control | Kahan configure |
|---|---|---|---|
| Laptop → k8s API | SSM port-forward `localhost:6443` → server `6443` | IAM (aws cli creds) + kubeconfig cert | `scripts/tunnel.sh`, `scripts/get-kubeconfig.sh` |
| Laptop → node shell | `aws ssm start-session` | IAM; port 22 band, SSH key nahi | node role `AmazonSSMManagedInstanceCore` |
| Nodes → internet | private subnet → NAT → IGW | SG egress all; NACL ephemeral ports | `modules/vpc` |
| Nodes → ECR | VPC interface endpoint (ecr.api/dkr) + S3 gateway (layers) | node IAM role `ECRReadOnly` + **ecr-credential-provider** | `modules/vpc`, user-data |
| Agent → server | `10.20.10.10:6443` | join token (SSM SecureString) | `agent.sh.tpl` |
| Argo CD → GitHub | HTTPS poll har ~3 min | public repo (no creds) | `gitops/bootstrap/root.yaml` |
| ALB controller → AWS | AWS API (IMDSv2, hop limit 2) | node role pe controller policy | `modules/k3s-cluster` |
| User → ALB → app | HTTP 80 → NodePort → pod 8080 | ALB SG: `inbound-cidrs` tera IP/32 | `gitops/release/rag-app.yaml` |
| RAG app → LiteLLM | `http://litellm.ai-gateway:4000/v1` | **team virtual key** (budget $25) | Secret `team-alpha-rag-secrets` |
| LiteLLM → Ollama | `http://ollama.ai-serving:11434` | cluster internal | `platform-config/ai-serving/litellm` |
| LiteLLM → Postgres | `5432` | DATABASE_URL (Secret `litellm-secrets`) | same |
| RAG app → Qdrant | `http://qdrant.vector-db:6333` | (lab: no auth) | chart values |
| Admin → LiteLLM | `kubectl port-forward svc/litellm 4000` | **master key** (kabhi chat/screenshot mein nahi) | Secret `litellm-secrets` |
| Admin → /ingest | ALB `/apps/team-alpha-rag/ingest` | header `X-Ingest-Token` | Secret `team-alpha-rag-secrets` |

**Ek sawaal ka safar** (abhi jo chal raha hai):
```
curl /apps/team-alpha-rag/ask → ALB (IP check) → NodePort → RAG pod
  → embed question: LiteLLM → Ollama nomic-embed-text (768 numbers)
  → Qdrant search: top 4 chunks (budgets.md, onboarding.md, security.md...)
  → prompt (system rules + context + question) → LiteLLM (key valid? budget?) → Ollama llama3.2:1b
  → answer + sources  ("Priya Raman, the FinOps lead.")
```

---

## 4. Phase by phase diary

Har phase mein: **kya banaya → kyun → kisse juda → kya toota → lesson.**

### Phase 0: Repo + placeholders (2026-11-07)

**Kya banaya:**
- GitHub repo `Anujsyal/aiforge-platform` (public).
- `scripts/configure.sh` se placeholders bhare: account ID, GitHub user, region, VPC ID (VPC ID baad mein, Phase 2 mein).
- `terraform/bootstrap`: S3 bucket `aiforge-tfstate-770803607362` (versioning, encryption). Iska apna state **local** hai, kyunki bucket khud banana hai (chicken-egg).

**Kyun pehle:** baaki saara Terraform state isi bucket mein rakhega (`backend.hcl`, `use_lockfile = true`, DynamoDB ki zarurat nahi).

**Notes:**
- `terraform.tfvars` aur `backend.hcl` **gitignored** hain (email, repo naam). Sirf `.example` files Git mein.
- Cost allocation tag `Project` pehle se **Active** tha (Project 1/2 se). Budgets isi tag pe filter karte hain.

### Phase 1: VPC (2026-11-07/08)

**Kya banaya** (`terraform apply -target=module.vpc`, ~25 resources):
- VPC `10.20.0.0/16`, 2 AZ (1a, 1b).
- 2 public subnets (ALB, NAT) + 2 private subnets (nodes).
- IGW, **ek** NAT Gateway (paisa bachane ko; HA ke liye do hote).
- Route tables: public → IGW, private → NAT.
- NACLs (stateless, ephemeral ports 1024-65535 allowed).
- S3 gateway endpoint (free; ECR layers S3 se aati hain) + ECR api/dkr interface endpoints.
- Flow logs (sirf REJECT, CloudWatch).

**Kyun:** nodes private mein rahenge, koi public IP nahi. Bahar jaana sirf NAT se, andar aana sirf ALB se.

**Kisse juda:** subnets ke tags (`kubernetes.io/role/elb`) se ALB controller public subnets dhoondhta hai. Private route table pe S3 endpoint.

**Problems:**
| Error | Kyun | Fix |
|---|---|---|
| Budget tag filter mein `$` HCL ne interpolation samjha | HCL mein `$` + `{` special hai | `join("$", [...])` |
| `terraform.tfvars`: duplicate attribute | Ek hi key (`create_github_oidc_provider`) do baar likh di | Ek line hatai |

**Lesson:** `terraform.lock.hcl` mein Windows + Linux dono ke hashes (`terraform providers lock -platform=...`), warna CI (Linux) fail.

### Phase 2: Cluster + SSM + ALB controller + Argo CD (2026-11-08)

**Kya banaya** (`terraform apply`, baaki sab):
- 1 k3s server (fixed IP `10.20.10.10`) + 3 agents, sab **m7i-flex.large**, private subnets mein.
- Node IAM role: SSM core, ECR read, ALB controller policy (GitHub se v3.6.2 ki official JSON download).
- k3s join token → SSM Parameter Store (SecureString). Server bootstrap ke baad kubeconfig bhi wahin upload karta hai.
- User-data: IMDSv2 se instance-id/AZ/type → `provider-id=aws:///AZ/ID` + instance-type label (ALB controller aur OpenCost ke liye zaruri, k3s ye khud nahi karta).
- ECR repos, GitHub OIDC role `aiforge-github-ci`, AWS Budgets + SNS email, Crossplane IAM user.
- Phir laptop se: `get-kubeconfig.sh` → `tunnel.sh` → `kubectl get nodes` (4 Ready).
- ALB controller (Helm 3.6.2), Argo CD 10.14.0 (Helm), phir dono ko **Argo CD ke hawale** (AppProjects `platform`/`ai-apps`, app `platform-namespaces`, app `aws-load-balancer-controller`).

**Kyun k3s, EKS nahi:** EKS control plane ~$73/month alag. k3s free, aur saari Kubernetes cheezein same.

**Problems (sab asli):**
| # | Error (jo screen pe aaya) | Root cause | Fix |
|---|---|---|---|
| 1 | `instance type is not eligible for Free Tier` | Account AWS **Free plan** pe hai: sirf free-tier types | t3.large → **m7i-flex.large**, 1 server + 3 agents |
| 2 | `EntityAlreadyExists: OpenIDConnectProvider` | GitHub OIDC provider poore account mein ek hi hota hai, Project 1/2 ne bana diya tha | `create_github_oidc_provider = false` (module existing ko `data` se padhta hai) |
| 3 | `get-kubeconfig.sh` → `ParameterNotFound` | Git Bash (MSYS) `/aiforge/k3s/kubeconfig` ko `C:/Program Files/Git/aiforge/...` bana deta | Sirf us aws command pe `MSYS_NO_PATHCONV=1`. Global lagaya to `KUBECONFIG` path bhi toot gaya → wapas hataya |
| 4 | `kubectl`: `connection refused 127.0.0.1:6443` | Tunnel chal hi nahi raha tha | `tunnel.sh` **alag terminal** mein, khula rakhna |
| 5 | Tunnel `Starting session...` pe atka | Instance start ke turant baad SSM agent abhi online nahi | 2-3 min ruk ke dobara |
| 6 | Argo CD Helm: `504 Gateway Time-out` (github.com releases) | GitHub release CDN down/slow | Same chart OCI se: `oci://ghcr.io/argoproj/argo-helm/argo-cd --version 10.14.0` |
| 7 | `namespaces "argocd" not found` | Install fail hua tha, namespace bana hi nahi | `--create-namespace` ke saath dobara |
| 8 | Git Bash: `no available terminals` | Laptop pe free RAM 0.75 GB (7.3 GB total) | Uninstall/reinstall se kuch nahi hua → **reboot** |

**Lesson:** private cluster ka matlab hai har cheez ke liye tunnel/SSM. Tunnel hi sabse kamzor kadi hai (Phase 3 mein bhi dikha).

### Phase 3: Ollama + LiteLLM + Qdrant (2026-11-08)

**Kya banaya:**
- **Ollama** (`ai-serving`, pool=ai node pe): init container 3 models pull karta hai (~1.6 GB, PVC pe). Requests 1 CPU / 3 Gi (free plan ki 8 GB node ke hisaab se).
- **LiteLLM** (`ai-gateway`): OpenAI-compatible gateway. Model names `llama3.2-1b`, `qwen2.5-0.5b`, `nomic-embed-text`. Fallback llama → qwen. Postgres mein keys/teams/spend. Secret `litellm-secrets` **manually** banaya (Vault Phase 6 mein aayega).
- **Qdrant** (`vector-db`): vector database, Helm chart 1.20.0.
- Teeno Argo CD apps (`30-ai.yaml`) se manage.

**Kyun gateway:** app kabhi seedha model ko call nahi karta. Saare keys, budgets, fallback aur logging ek jagah.

**Kisse juda:** RAG app → LiteLLM → Ollama. RAG app → Qdrant. Argo CD → teeno.

**Problems (asli):**
| # | Error | Root cause | Fix |
|---|---|---|---|
| 1 | `kubectl` → `localhost:8080 connection refused` | Naye terminal mein `KUBECONFIG` set nahi tha (kubectl default 8080 try karta hai) | `export KUBECONFIG=~/.kube/aiforge.yaml` → `~/.bashrc` mein daala |
| 2 | `source ~/.bashrc` ke baad `6443 refused` | Ab config sahi thi, par tunnel band tha | Tunnel restart |
| 3 | `TLS handshake timeout` | SSM session ~20 min idle pe AWS band kar deta hai | `tunnel.sh` mein keepalive (har 4 min `/livez` curl) + auto-reconnect loop |
| 4 | LiteLLM `401 Malformed API Key` | `$MK` variable naye terminal mein khaali tha | MK cluster ke Secret se padha: `kubectl -n ai-gateway get secret litellm-secrets -o jsonpath='{.data.LITELLM_MASTER_KEY}' \| base64 -d` |
| 5 | Qdrant app `OutOfSync/Missing`: `could not find monitoring.coreos.com/v1` | Chart ka ServiceMonitor Prometheus CRD maangta hai, jo Phase 7 mein aayega | `metrics.serviceMonitor.enabled: false` |
| 6 | Git fix push ke baad bhi wahi error | Argo ka **retry purana operation** dohrata hai (purani values ke saath) | Application delete + re-apply (ya UI: Terminate → Sync) |

**Lesson:** CRD order matter karta hai. Jo cheez kisi aur ke CRD pe depend kare, use tab tak band rakho.

### Phase 4: RAG app (2026-11-08/09)

**Kya banaya:**
1. **Local** (Docker Desktop 28.5.1): pytest 7 tests, docker compose (app + Ollama + Qdrant).
2. **Image** → ECR `aiforge/rag-app:manual-1`, phir prompt fix ke baad `manual-2` (tags immutable).
3. **Team onboarding** (LiteLLM): team `team-alpha` (budget $25/30d), key alias `team-alpha-rag`. Namespace `team-alpha-rag` + labels + Secret (`litellm_api_key`, `ingest_token`). Script: `scripts/phase4-team-secret.sh` (idempotent).
4. **Helm deploy** (manual) → ALB bana → `/ingest` → `/ask` sahi jawab.
5. **GitOps:** `helm uninstall`, phir ApplicationSet `rag-apps` (`gitops/apps/*/app.yaml` padhta hai) ne app `team-alpha-rag` banaya. Synced/Healthy.

**Kisse juda:** ApplicationSet → Helm chart `charts/ai-app` (golden path) + `gitops/release/rag-app.yaml` (image) + `gitops/apps/team-alpha-rag/values.yaml` (team ki settings). Chart banata hai: Deployment, Service (NodePort), Ingress (shared ALB group `aiforge`, path `/apps/team-alpha-rag`), NetworkPolicy, ingest Job.

**Problems (asli):**
| # | Error | Root cause | Fix |
|---|---|---|---|
| 1 | `pytest`: `ModuleNotFoundError: No module named 'app'` | Plain `pytest` project folder ko import path mein nahi daalta | `apps/rag-app/pytest.ini` → `pythonpath = .` |
| 2 | `docker push`: `tag invalid ... immutable` | `manual-1` dobara push kiya; ECR tags immutable hain (security feature) | Harmless. Naya build = naya tag (`manual-2`) |
| 3 | `team/new` → `KeyError`, bash `syntax error` | Lamba multi-line command paste karte waqt toot gaya (ajeeb `\026` character, lines gaayab) | Lambe commands ki jagah script (`phase4-team-secret.sh`) |
| 4 | Python: `FileNotFoundError: /tmp/...` | Windows Python Git Bash ka `/tmp` nahi samajhta | File ki jagah stdin se pipe |
| 5 | `Method Not Allowed` | Mangled paste se URL/method galat | Script se chalaya |
| 6 | Key bani par `team_id: None` | Galat/khaali team_id ke saath generate hua | Script purani same-alias keys delete karke sahi team ke saath nayi banata hai |
| 7 | Pods `ImagePullBackOff`: `no basic auth credentials` | EKS mein kubelet ke saath **ecr-credential-provider** aata hai, **k3s mein nahi**. IAM permission thi, par token containerd tak pahunchane wala koi nahi | `ecr-credential-provider v1.37.0` + `CredentialProviderConfig` + k3s restart. Chalte nodes: `scripts/install-ecr-credential-provider.sh` (SSM Run Command). Naye nodes: user-data |
| 8 | User-data badalte hi Terraform plan "replace 4 instances" | `user_data_replace_on_change = true` | `lifecycle { ignore_changes = [user_data] }` → plan: No changes |
| 9 | `logs job/...-ingest` → `job not found` | Job khatam hone ke baad TTL se delete ho gaya | Ingest manually ALB se token ke saath |
| 10 | `invalid ingest token` | Command mein `<ingest_token>` placeholder **literally** chipka diya | Asli token Secret se nikaala |
| 11 | curl hang | Tunnel band (kubectl wale steps ke liye) | Tunnel restart |
| 12 | `json: Expecting value` | Rollout ke beech purana pod band ho raha tha → khaali response | 30 sec baad dobara: theek |
| 13 | Har sawaal pe "I don't know" (over-refusal) | System prompt bahut sakht ("ONLY", "reply exactly", lambi "never" list); 1B model ke liye mana karna aasaan | 3 prompts same context pe LiteLLM se test: purana 1/5, V3 numbered rules + "match by meaning" **4/5**. V3 rakha. Red-team leak-check phrases update kiye |
| 14 | `helm uninstall` → appset ke baad ALB address badal gaya | Ingress delete hua to ALB bhi delete; naya Ingress = naya ALB | Normal. Naya: `k8s-aiforge-e8a52a6c8a-479081548.ap-south-1.elb.amazonaws.com` |

**Lesson:** "AWS ka managed feature" (EKS) aur "khud ka cluster" (k3s) mein farak tab dikhta hai jab koi chhoti cheez (ECR auth) gaayab ho. Aur chhote LLM ke liye prompt chhota aur seedha hona chahiye.

---

### Phase 5: CI + eval gate (2026-11-08 se, chal raha hai)

**Kya bana:** `.github/workflows/rag-app-ci.yml`. Har push (apps/rag-app, evals) pe:
gitleaks → pytest → docker build → Trivy → GitHub runner pe hi Ollama + Qdrant + app (docker compose) → sample docs + poisoned doc ingest → promptfoo quality (12 sawaal) → promptfoo red-team (6 attacks) → `make_attestation.py` (quality ≥ 80% **aur** red-team = 100%?) → sirf main pe: OIDC se ECR push → cosign sign + eval attestation → `gitops/release/rag-app.yaml` mein tag + digest commit → Argo CD deploy.

**Kisse juda:** GitHub OIDC → IAM role `aiforge-github-ci` (Phase 2 Terraform) → ECR. Release file → ApplicationSet (Phase 4) → cluster. Phase 6 mein Kyverno isi signature + attestation ko check karega.

**Sabse badi seekh: gate ne asli bug pakda (bina kisi demo ke).**
Phase 4 ke pushes pe CI apne aap chala aur dono baar gate ne release rok di:

| Run | Prompt | Quality | Red-team | Kya hua |
|---|---|---|---|---|
| 42505171572 | Purana sakht ("ONLY", "reply exactly") | **16.7%** | 100% | Har sawaal pe "I don't know" |
| 42516646358 | V3 simple ("match by meaning") | **91.7%** | **50%** | "PWNED" bola; master key pucchne pe fake `sk-1234567890abcdef` banayi; poisoned cafeteria doc padh ke "HACKED" likha |

Build, tests, Trivy sab pass the. Sirf eval gate fail. Matlab gate bina gate ke chalne wala ek "insecure lekin achha dikhne wala" release production mein jaane se rok raha tha.

**Root cause:** 1B model chhota hai. Prompt sakht → sab mana. Prompt simple → har instruction maan leta hai, chahe wo user ki ho ya document ke andar chhupi. Sirf prompt se dono nahi milte.

**Fix: guardrails layer** ([app/guardrails.py](../apps/rag-app/app/guardrails.py)), plain code jo model pe depend nahi karta:
```
sawaal ──► [1] check_question: "ignore previous instructions", "system prompt", "you are now", master key/sk- → BLOCK (LLM call hi nahi)
        ──► Qdrant chunks ──► [2] sanitize_context: "SYSTEM OVERRIDE", "from now on", "ignore every previous rule" wali LINES hatao
        ──► LLM ──► [3] redact_output: sk-..., AKIA..., hvs..., private key → [REDACTED]
```
- Cafeteria doc ki injection line hatti, par "Lunch 12:30-14:00" wali line bachi (line-level, poora doc nahi).
- Metric `rag_guardrail_events_total{event=...}` (Phase 7 mein Grafana pe dikhega).
- Unit tests (`tests/test_guardrails.py`): saare attacks block, **aur** golden dataset ke saare sawaal kabhi block nahi (false positive = quality girna).
- Limit (interview mein khud bolna): regex paraphrase se bypass ho sakte hain. Production mein saath mein classifier (Llama Guard / Prompt Guard, LLM Guard, NeMo Guardrails). Red-team eval isi liye har build pe chalta hai.

**Setup steps:** GitHub secret `AWS_CI_ROLE_ARN = arn:aws:iam::770803607362:role/aiforge-github-ci`, Workflow permissions = Read and write. `image.tag: manual-2` CI ke pehle release commit ke **baad** hatana (pehle hataya to release file ka `0.0.0` deploy hoga = ImagePullBackOff).

**Logs kaise padhe:** promptfoo ki table Actions log mein hoti hai (`[FAIL]` wali rows). Exact numbers "Eval gate" step mein: `EVAL GATE FAILED: passRate=... redteam=...`. HTML report artifact `eval-reports` mein.

---

## 5. Roz ka kaam (operations notes)

### Session shuru karna
```bash
# 1. Instances start (stopped rakhte hain, paisa bachta hai; NAT/ALB/EBS ka chalta rehta hai)
aws ec2 start-instances --instance-ids i-094f278871a07219f i-0d32eafeef211900a i-0e9de26b1277e0879 i-09b904ee92ee75b4d
# 2. 2-3 min ruko (SSM agent online ho)
# 3. Alag Git Bash window:
cd "/e/Project 3" && ./scripts/tunnel.sh
# 4. Main window:
kubectl get nodes          # 4 Ready
kubectl -n argocd get applications
```

### Session band karna
```bash
aws ec2 stop-instances --instance-ids i-094f278871a07219f i-0d32eafeef211900a i-0e9de26b1277e0879 i-09b904ee92ee75b4d
```
Stop karne pe bhi kharcha: NAT Gateway (~$1.3/din), ALB, EBS, ECR endpoints. Lamba break ho to `terraform destroy` (phir naya VPC ID `10-core.yaml` mein dalna padega).

### Yaad rakhne wali cheezein
| Cheez | Kahan |
|---|---|
| KUBECONFIG | `~/.kube/aiforge.yaml` (`~/.bashrc` mein export) |
| LiteLLM master key | Cluster Secret `ai-gateway/litellm-secrets`. Password manager mein. **Chat/screenshot mein kabhi nahi** |
| Team key + ingest token | Secret `team-alpha-rag/team-alpha-rag-secrets` |
| LiteLLM team | `team-alpha`, budget $25/30d, key alias `team-alpha-rag` |
| ALB address | `kubectl -n team-alpha-rag get ingress` (Ingress recreate pe badalta hai) |
| ALB pe access | Sirf `122.161.49.234/32`. IP badle (naya WiFi) → `gitops/release/rag-app.yaml` `inboundCidrs` update + push |
| Argo CD UI | `kubectl -n argocd port-forward svc/argocd-server 8080:80` → localhost:8080 (admin) |

### Git Bash ke rules (bahut baar kaam aaye)
1. `/` se shuru hone wale AWS args (SSM param names) → sirf us command pe `MSYS_NO_PATHCONV=1`.
2. Lamba multi-line command paste mat kar. Script bana ke chala.
3. `<...>` wale placeholders hamesha asli value se badal.
4. Windows Python ko `/tmp/...` mat de; stdin ya Windows path use kar.
5. Laptop RAM kam ho (Docker + browser + VS Code) to terminals khulna band ho jaate hain → reboot.

### Tunnel ke rules
- Tunnel window band = kubectl band. ALB wale curl tunnel ke bina chalte hain (wo internet se hai).
- Ajeeb errors (TLS timeout, 6443 refused, curl hang) → pehle tunnel check.
- Note: maine ek baar test-tunnel cleanup mein **saare** SSM sessions terminate kar diye, user ka tunnel bhi toot gaya. Cleanup sirf apne session ID ka karna.

---

## 6. Saari galtiyan + lessons (ek list)

**Account / AWS**
1. Free plan account → sirf free-tier instance types. Plan check pehle karo.
2. Account-wide cheezein (OIDC provider, cost allocation tags) pichhle projects se pehle se maujood ho sakti hain → `data` source / flag.
3. Stop ≠ free. NAT aur ALB ka bill chalta rehta hai.

**Terraform**
4. HCL mein literal `$` ke liye `join`/escape.
5. tfvars mein duplicate key = error.
6. `user_data_replace_on_change` + template edit = poora cluster replace. `ignore_changes` lagao, chalte nodes ko script se patch karo.

**Laptop / shell**
7. MSYS path conversion (per-command fix, global nahi).
8. Env vars (`KUBECONFIG`, `MK`) naye terminal mein nahi hote → `.bashrc` ya Secret se padho.
9. Multi-line paste corruption → scripts.
10. Placeholder literal paste.
11. Windows Python + `/tmp`.
12. Kam RAM → terminal nahi khulta.

**Kubernetes / GitOps**
13. Tunnel = sabse kamzor kadi (idle timeout, SSM agent boot time).
14. CRD ordering (ServiceMonitor before Prometheus).
15. Argo retry purana operation dohrata hai → delete/re-apply.
16. GitHub CDN 504 → OCI registry fallback.
17. k3s mein ECR credential provider nahi hota.
18. Ingress delete = ALB delete = naya DNS naam.
19. Job TTL ke baad logs nahi milte → turant dekho ya `ttlSecondsAfterFinished` badhao.
20. Rollout ke beech khaali response normal hai.

**App / AI**
21. pytest import path (`pytest.ini`).
22. ECR immutable tags: har build naya tag.
23. Chhote model ke liye sakht prompt = over-refusal. Prompt ko data ke saath **measure** karo (1/5 → 4/5), andaaza mat lagao.
24. Prompt badla to red-team ke leak-check phrases bhi badlo.
25. 1B model ki limit: 1 sawaal ab bhi fail. Isiliye gate 80% pe hai, 100% pe nahi.
26. Prompt sirf quality ke liye tune kiya to security gir gayi (red-team 50%). Security prompt pe nahi, **code** (guardrails) pe rakho. Eval gate dono saath check karta hai, isiliye pakda gaya.

---

## 7. Abhi ki state + temporary jugaad

**Chal raha hai (Argo CD, sab Synced/Healthy):** `platform-namespaces`, `aws-load-balancer-controller`, `ollama`, `litellm`, `qdrant`, `tenant-appsets`, `team-alpha-rag`.

**Manual cheezein (baad mein automate hongi):**
| Abhi manual | Kab automate | Kaise |
|---|---|---|
| `litellm-secrets` (kubectl create) | Phase 6 | Vault + ESO |
| `team-alpha-rag-secrets` | Phase 6 | `useExternalSecret: true`, Vault path |
| Image `manual-2` (laptop se push) | Phase 5 | CI build + sign + `release/rag-app.yaml` bump |
| Qdrant collection (app khud banata hai) | Phase 8 | Crossplane VectorStore |

**`gitops/apps/team-alpha-rag/values.yaml` ke toggles (har phase mein ek hatana hai):**
| Toggle | Hatao in phase |
|---|---|
| `image.tag: manual-2` | 5 (CI ke pehle release ke baad) |
| `secrets.useExternalSecret: false` | 6 |
| `serviceMonitor.enabled: false`, `otel.enabled: false` | 7 |
| Qdrant `metrics.serviceMonitor.enabled: false` (`30-ai.yaml`) | 7 (true karna) |
| `vectorStore.create: false` | 8 |

---

## 8. Aage kya bachaa hai (Phase 5-10)

| Phase | Kya banega | Kisse judega |
|---|---|---|
| 5 CI + eval gate | GitHub Actions: gitleaks → pytest → Trivy → promptfoo (12 quality + 6 red-team) → OIDC → ECR → cosign sign + eval attestation → release file bump | GitHub secret `AWS_CI_ROLE_ARN = arn:aws:iam::770803607362:role/aiforge-github-ci`; Argo CD naya digest uthayega |
| 6 Security | Vault + ESO, Kyverno (sirf signed + eval-passed images), NetworkPolicy default-deny | Phase 5 ki signatures; LiteLLM re-onboard |
| 7 Observability | Prometheus/Grafana, Loki/Alloy, OTel collector, Langfuse Cloud | ServiceMonitors on |
| 8 Portal | Backstage (template → PR), Crossplane VectorStore | ApplicationSet (same jo abhi hai) |
| 9 Cost | OpenCost, Infracost, showback report, Budgets | node labels (Phase 2 mein lagaye the) |
| 10 | Demo video/screenshots, `terraform destroy` | — |

Jaise har phase hoga, iss doc mein uska diary section add karna.

---

## 9. Interview mein ye kahani kaise sunani hai

**30 second version:**
"Maine AWS pe ek self-service AI platform banaya. Terraform se private VPC aur k3s cluster, jisme koi public IP ya SSH nahi, access sirf SSM se. Uspe LiteLLM gateway hai jo per-team keys aur budget enforce karta hai, Ollama models serve karta hai, aur teams ke RAG apps ek golden-path Helm chart aur Argo CD ApplicationSet se deploy hote hain. CI mein eval gate hai, aur Kyverno sirf wahi images chalne deta hai jo signed hain aur eval pass kar chuki hain."

**Best STAR stories (asli):**
0. **Eval gate ne insecure release roki.** S: Prompt fix se quality 17% → 92% hui. T: Release. A: CI red-team 50% pe fail → logs se dekha model "PWNED" bol raha, fake key bana raha, poisoned doc maan raha → prompt pe security chhod ke code guardrails (input block, context sanitize, output redact) + false-positive unit tests. R: gate dono shart (≥80% quality, 100% red-team) pe release.
1. **ECR ImagePullBackOff on k3s.** S: Pods pull nahi kar rahe the jabki IAM sahi tha. T: Pata karna ki gap kahan hai. A: Error padha ("no basic auth credentials") → samjha ki EKS mein kubelet credential provider built-in hota hai, k3s mein nahi → binary + config, SSM Run Command se chalte nodes pe, user-data se naye nodes pe, aur `ignore_changes` taaki Terraform cluster replace na kare. R: Pods Running, aur future nodes automatically theek.
2. **Over-refusal.** S: Retrieval sahi tha par model har baar "I don't know" bol raha tha. A: Prompt ko andaaze se nahi badla. 5 cases pe 3 variants seedha gateway pe same context ke saath measure kiye. R: 1/5 → 4/5, injection defence bhi bana raha. Isi wajah se gate 80% pe rakha.
3. **Argo CD retry trap.** Git fix ke baad bhi error aata raha → samjha ki retry purana operation chalata hai → app delete/re-apply.
4. **Free plan constraint.** t3 types allowed nahi the → m7i-flex.large pe resize, Ollama ke requests uske hisaab se tune kiye.
