# OpenTofu — Cell Provisioning

This directory holds the **Cell Provisioning** layer, migrated from
`infra/platform-b-cell` (Terraform) to a `cells/` + `modules/` OpenTofu
layout. It replaces `infra/platform-b-cell` entirely.

## Layout

```
opentofu/
  modules/              # One directory per reusable component. No cell- or
                         # tenant-specific values live here — everything is
                         # parameterized via variables.
    bedrock-enablement/
    policy-engine/       # KMS-encrypted Policy Engine + baseline Cedar policy
    gateway/             # AgentCore Gateway (AWS_IAM authorizer)
    guardrail/           # Default content guardrail
    runtime-iam/         # Runtime IAM role, logs, Bedrock invocation logging
    cell-observability/  # Admin + Model Gateway API debug logs
    cell-cost/           # Per-cell CUR2.0 export bucket

  cells/
    cell1/               # Composition root for Cell 1 — wires the modules
                         # above together in dependency order (see main.tf).
      backend.tf         # OpenTofu block + S3 state backend
      variables.tf
      main.tf
      outputs.tf
      env/
        us-east-1/
          dev.tfvars     # Per-region, per-environment variable overrides
```

## Adding a new cell

1. Copy `cells/cell1/` to `cells/cell2/`.
2. Change the `backend.tf` state `key` to `cells/cell2/terraform.tfstate`.
3. Set `cell_name = "cell2"` (and any other overrides) in a new
   `env/<region>/<env>.tfvars`.
4. Point a new Harness IaCM workspace at `opentofu/cells/cell2`,
   `provisioner = opentofu`.

No module changes required — that's the point of splitting modules out from
the per-cell composition root.

## What moved here from `infra/platform-a` (Cell Provisioning items)

- Bedrock enablement check
- CloudWatch logs for admin + Model Gateway API debugging
- Bedrock invocation logs (platform/tenant debugging AND cost analysis)
- S3 bucket for CUR2.0 exports — now created **per cell** instead of once
  globally

## What moved OUT of the old `infra/platform-b-cell` (Tenant Onboarding items)

The following were re-tagged as Tenant Onboarding and now live in
`infra/tenant-registration/main.tf` instead:

- Base IAM roles/policies in the Cell 1 account (`cell_base_automation`)
- Cross-account IAM roles/policies for Model Gateway → Bedrock routing
  (`model_gateway_to_bedrock`)

## Changes made in this pass

- **S3 bucket per cell** — `modules/cell-cost` is instantiated once per cell,
  so each cell gets its own CUR export bucket.
- **KMS encryption for the Policy Engine** — `modules/policy-engine` now
  creates a customer-managed KMS key (`encryption_key_arn`) instead of
  relying on the AWS-managed default key.
- **Cognito User Pool removed** — the Gateway's authorizer switched from
  `CUSTOM_JWT` (which needed a Cognito User Pool purely to provide a
  reachable OIDC discovery URL) to `AWS_IAM` (SigV4-signed requests,
  `bedrock-agentcore:InvokeGateway` permission, no external identity
  provider needed at all).

## Not yet done (repo structure only — "update now, test later")

- The Harness IaCM workspace `toyota_full_platform_b` has been repointed at
  `opentofu/cells/cell1` with `provisioner = opentofu`, but this has **not**
  been planned/applied yet.
- Because the old `infra/platform-b-cell` state's resource addresses don't
  match this module-based layout, expect the first `plan` here to show a
  full destroy+recreate of every AgentCore resource in this cell, not an
  in-place update.
