# AIForge Security Rules

Applications must never call external AI providers such as OpenAI or Anthropic directly.
All model traffic goes through the LiteLLM gateway at litellm.ai-gateway.svc.
Kubernetes NetworkPolicies in every team namespace deny all egress except to the gateway, the vector database and the telemetry collector.

Container images must be signed with cosign by the CI pipeline and must carry an eval attestation.
Kyverno blocks any pod whose image is unsigned or whose eval pass rate is below 80 percent.

API keys are stored in HashiCorp Vault and synced into the cluster by the External Secrets Operator.
Developers never see the LiteLLM master key.

Nobody connects to the cluster nodes with SSH. Engineers use AWS SSM Session Manager instead.
The on-call rotation for the platform is called "Forge Watch" and changes every Monday at 10:00 IST.
