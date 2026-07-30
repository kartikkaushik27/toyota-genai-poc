# Toyota GenAI Platform — POC

A single-account, delegate-free reproduction of the Toyota GenAI Bedrock/AgentCore
platform architecture, built to run entirely through Harness pipelines.

## Scope note

The real design spans **three separate AWS accounts** (Platform, Cell, Tenant) and
a full AgentCore Gateway + Cedar Policy Engine. This POC runs in **one AWS account**
(`915632791698`, `us-east-1`) with a **single short-lived AWS session**, so:

- Cross-account IAM is simulated with same-account roles + `sts:AssumeRole` trust
  policies (same pattern, fewer accounts).
- AgentCore Gateway + Policy Engine (Cedar) are out of scope for this POC — the
  Runtime + Guardrail + Memory pattern is the core "agentic" story that's included.
- Everything runs on **Harness Cloud runners** (no self-hosted Delegate needed),
  since this account has none installed.

## Structure

| Path | Mirrors | Pipeline |
|---|---|---|
| `infra/platform/*.tf` | "Platform Infrastructure" requirements (DynamoDB, S3, CloudWatch, ECR, IAM) | Pipeline 1 — Platform Infra Provision |
| `infra/tenant/onboard.sh` | "Tenant Onboarding" requirements (Guardrail, IAM role, log group, DynamoDB record) | Pipeline 2 — Tenant Onboarding |
| `agent/` | AgentCore Runtime container contract (`/invocations`, `/ping`, port 8080, ARM64) | Pipeline 3 — Agent CI Build |
| *(Pipeline 4 calls AWS CLI directly against the built image)* | AgentCore Runtime deploy dev → approval → prod | Pipeline 4 — Agent CD Deploy |

## Resource naming

All AWS resources are prefixed `toyota-poc-*` for easy identification and cleanup.
