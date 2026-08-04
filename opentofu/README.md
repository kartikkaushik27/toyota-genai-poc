# OpenTofu — Cell Provisioning

This directory holds the **Cell Provisioning** layer, migrated from
`infra/platform-b-cell` (Terraform) to a `cells/` + `modules/` OpenTofu
layout. It replaces `infra/platform-b-cell` entirely.

## Layout

```
opentofu/
  modules/              # One directory per reusable component. No cell-,
                         # region- or tenant-specific values live here —
                         # everything is parameterized via variables.
    naming/              # The single platform-wide project prefix
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
      providers.tf       # terraform block + provider. No backend, no region.
      variables.tf       # cell_name — and nothing else
      main.tf
      outputs.tf
```

There are no per-region directories or `.tfvars` files. The same
`cells/cell1` directory provisions every region.

## Where state lives

Nowhere in this repo. There is **no backend block**: Harness IaCM stores and
versions the state for each workspace itself, pulling it before a plan and
uploading it after an apply. Declaring an S3 backend would create a second,
competing copy of the truth.

One workspace = one state = one cell instance.

## How region and variables reach the cell

Region is **not** a variable and **not** a pipeline input. A cell instance is
the pair *(cell, region)*, and the only thing that differs between the two
instances is the `AWS_DEFAULT_REGION` environment variable set on the
workspace, which the AWS provider reads (`provider "aws" {}` declares no
region).

```
provision-cell pipeline: cell_name, aws_connector
        ↓  bootstrap stage creates one workspace per region
IaCM workspace  cell1_us_east_1   AWS_DEFAULT_REGION=us-east-1  ─┐
IaCM workspace  cell1_us_west_2   AWS_DEFAULT_REGION=us-west-2  ─┤
        ↓                                                       │
opentofu/cells/cell1  →  opentofu/modules/*  (same code both) ───┘
```

`cell_name` is declared with **no default**: Harness variable precedence is
workspace variables > variable sets > HCL defaults, so with no default a
missing input fails loudly instead of quietly provisioning something named
`cell1`.

`project_prefix` is not an input either — there is exactly one platform-wide
prefix, defined once in `modules/naming`.

### Region is part of every resource name

`cells/cell1/main.tf` derives `local.cell_id = "<cell>-<region>"` from
`data.aws_region.current` and passes that down to every module, so cell1 in
us-east-1 produces `toyota-full-cell1-us-east-1-runtime-role` and so on.

This is required, not cosmetic: IAM role names and S3 bucket names are
**global**, so two regional instances of the same cell would collide on them.
Regional resources (log groups, guardrails, gateways) carry the region too,
purely so the naming is uniform and the next global resource someone adds is
safe by default.

Anything looking a cell role up by name must include the region —
`infra/runtime-dev`, `infra/runtime-prod` and `infra/tenant-agentic` do this
via their own `data.aws_region.current`, which resolves to the cell instance
in the same region they deploy into.

## The pipeline

`Provision Cell` (`provision_cell`), YAML in
`harness/pipelines/provision-cell.yaml`. Inputs: `cell_name` and
`aws_connector`. Stages:

1. **Ensure Cell Workspaces** (CI) — for each region in `REGIONS`, creates the
   `<cell>_<region>` workspace if it does not already exist. Idempotent, so
   every run is safe.
2. **Provision us-east-1** (IaCM) — init → plan → approval → apply against
   `<+pipeline.variables.cell_name>_us_east_1`.
3. **Provision us-west-2** (IaCM) — the same against `..._us_west_2`.

Because stage 1 creates the workspaces, onboarding a cell needs no manual
setup in the UI and no helper script.

Harness validates the AWS connector when a workspace is **saved**, so
`provider_connector` cannot be a runtime expression. That is why
`aws_connector` is consumed at workspace-creation time; on later runs it must
match the connector already pinned to the workspace.

### Local runs

```bash
AWS_DEFAULT_REGION=us-west-2 tofu plan -var cell_name=cell1
```

## Adding a new cell

1. Copy `cells/cell1/` to `cells/cell2/`.
2. Run `Provision Cell` with `cell_name=cell2`.

That's it — the bootstrap stage creates `cell2_us_east_1` and
`cell2_us_west_2`, and no module changes are needed. That's the point of
splitting modules out from the per-cell composition root.

Note that passing a different `cell_name` to an existing workspace renames
resources **inside that cell's state**; it does not create a second cell. A
real second cell gets its own workspaces, as above.

## Adding a new region

Add it to `REGIONS` in the bootstrap stage **and** add a matching IaCM stage
in `harness/pipelines/provision-cell.yaml`. The stage list cannot be
generated from the list in the script.

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

## Changes made in this restructuring

- **S3 bucket per cell** — `modules/cell-cost` is instantiated once per cell,
  so each cell gets its own CUR export bucket.
- **KMS encryption for the Policy Engine** — `modules/policy-engine` creates a
  customer-managed KMS key (`encryption_key_arn`) instead of relying on the
  AWS-managed default key. The Gateway role is granted `kms:Decrypt` /
  `DescribeKey` / `GenerateDataKey` / `CreateGrant` on that key, without which
  `CreateGateway` fails with "Access denied while calling GetPolicyEngine".
- **Cognito User Pool removed** — the Gateway's authorizer switched from
  `CUSTOM_JWT` (which needed a Cognito User Pool purely to provide a
  reachable OIDC discovery URL) to `AWS_IAM` (SigV4-signed requests,
  `bedrock-agentcore:InvokeGateway` permission, no external identity provider
  needed at all).
- **Region removed from code and inputs** — every run provisions both
  us-east-1 and us-west-2 from one region-agnostic directory.
- **S3 backend removed** — state is held by Harness IaCM only.
