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

## How variables reach the cell

`cells/cell1/variables.tf` declares `cell_name` and `aws_region` with **no
defaults** — the cell is a pure "declare inputs, call modules" shell. Values
come from the run-time chain:

```
provision-cell pipeline variables
        ↓  (<+pipeline.variables.NAME>)
IaCM workspace OpenTofu variables
        ↓
opentofu/cells/cell1  →  opentofu/modules/*
```

Harness variable precedence is workspace variables > variable sets > HCL
defaults, so with no defaults in code a missing pipeline input fails loudly
instead of quietly provisioning something named `cell1`.

`project_prefix` is **not** an input. There is exactly one platform-wide
prefix, defined once in `modules/naming` and consumed by every cell.

The pipeline is `Provision Cell` (`provision_cell`) — YAML kept in
`harness/pipelines/provision-cell.yaml`. Inputs at run time are `cell_name`,
`aws_region` and `aws_connector`; it then runs init → plan → approval →
apply.

### One workspace per cell

The stage's workspace is resolved from the cell name
(`workspace: <+pipeline.variables.cell_name>`), so `cell_name=cell1` targets
the `cell1` workspace and its own state. The pipeline never needs editing
when a cell is added.

Harness validates the AWS connector when a workspace is **saved**, so
`provider_connector` cannot be a runtime input — the connector is pinned per
cell workspace. `aws_connector` is therefore a pipeline input that must match
the connector on the target cell workspace, and it is the input used when
onboarding the cell:

```bash
export HARNESS_API_KEY=pat....
export HARNESS_ACCOUNT_ID=...
harness/scripts/create-cell-workspace.py \
    --cell cell2 --region us-west-2 --aws-connector aws_cell2
```

For a local run, pass the tfvars file explicitly (it is not auto-loaded,
since it isn't named `terraform.tfvars` / `*.auto.tfvars`):

```bash
tofu plan -var-file=env/us-east-1/dev.tfvars
```

## Adding a new cell

1. Copy `cells/cell1/` to `cells/cell2/`.
2. Change the `backend.tf` state `key` to `cells/cell2/terraform.tfstate`.
3. Set `cell_name = "cell2"` (and any other overrides) in a new
   `env/<region>/<env>.tfvars` for local runs.
4. Create a new Harness IaCM workspace pointed at `opentofu/cells/cell2`,
   `provisioner = opentofu`, with its OpenTofu variables set to the same
   `<+pipeline.variables.*>` expressions as the cell1 workspace.
5. Run the existing `Provision Cell` pipeline and pick that workspace — the
   pipeline itself needs no changes, since the workspace is a runtime input.

One workspace = one state file = one cell. Passing a different `cell_name`
to an existing cell's workspace renames resources **inside that cell's
state**; it does not create a second cell. A real second cell needs its own
workspace as described above.

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
