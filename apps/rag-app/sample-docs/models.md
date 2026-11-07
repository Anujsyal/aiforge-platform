# AIForge Model Catalog

The default chat model is llama3.2-1b, served by Ollama on CPU nodes.
If llama3.2-1b fails or times out, the gateway automatically falls back to qwen2.5-0.5b.
The embedding model is nomic-embed-text, which produces 768-dimensional vectors.

All models are self-hosted inside the VPC, so prompts and documents never leave the AWS account.
The models run on the k3s agent node that carries the label aiforge.io/pool=ai.

Answer quality is checked in CI by promptfoo. A release is blocked when fewer than 80 percent of the eval cases pass.
RAGAS faithfulness and answer relevancy scores are recorded for every build as an advisory report.
