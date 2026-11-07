# AIForge Team Budgets

Every team that onboards to AIForge gets a default LLM budget of 25 USD per month.
The budget is enforced by the LiteLLM gateway through the team's virtual key.
When a team crosses 80 percent of its budget, the platform team receives a Slack warning.
When the budget is fully used, the gateway rejects new requests with HTTP 429 until the next month.

A team can request a budget increase by opening a ticket in the "forge-requests" GitHub project.
Budget increases above 100 USD per month need approval from the FinOps lead, Priya Raman.

Internal model prices used for showback:
- llama3.2-1b costs 0.20 USD per million input tokens and 0.40 USD per million output tokens.
- qwen2.5-0.5b costs 0.10 USD per million input tokens and 0.20 USD per million output tokens.
- nomic-embed-text costs 0.02 USD per million tokens.

These are internal prices that represent the shared GPU and CPU cost; they are not vendor prices.
