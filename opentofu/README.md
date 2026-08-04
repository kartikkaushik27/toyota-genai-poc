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

  cells/                # THE composition root — one directory for every cell
                         # instance. Wires the modules above together in
                         # dependency order (see main.tf).
    providers.tf         # terraform block + provider. No backend, no region.
    variables.tf         # cell_name + cell_type — and nothing else
    main.tf
    outputs.tf
```

There is no `cells/cell1`, `cells/cell2`, ... and no per-region directories or
`.tfvars` files. A per-cell directory would be a byte-for-byte copy of this
one, and copies drift; which instance a run provisions is decided by the
pipeline inputs instead.

## Where state lives

Nowhere in this repo. There is **no backend block**: Harness IaCM stores and
versions the state for each workspace itself, pulling it before a plan and
uploading it after an apply. Declaring an S3 backend would create a second,
competing copy of the truth.

One workspace = one state = one cell instance.

## What identifies a cell instance

A cell instance is the triple *(cell_name, cell_type, region)*:

- **cell_name** — which cell, e.g. `cell1`
- **cell_type** — which environment it serves: `dev`, `test`, `stage`, `prod`
- **region** — not a variable and not a pipeline input; it arrives only as
  `AWS_DEFAULT_REGION` on the workspace, which the AWS provider reads
  (`provider "aws" {}` declares no region)

Each instance owns one workspace, therefore one state:

```
provision-cell pipeline: cell_name=cell1, cell_type=dev, aws_connector
        ↓  bootstrap stage creates one workspace per region
IaCM workspace  cell1_dev_us_east_1   AWS_DEFAULT_REGION=us-east-1  ─┐
IaCM workspace  cell1_dev_us_west_2   AWS_DEFAULT_REGION=us-west-2  ─┤
        ↓                                                           │
opentofu/cells  →  opentofu/modules/*   (same code for both) ────────┘
```

Workspace identifiers use underscores (`cell1_dev_us_east_1`) because Harness
identifiers allow only letters, digits and underscores; the workspace **name**
keeps the readable `cell1-dev-us-east-1` form.

`cell_name` and `cell_type` are declared with **no default**: Harness variable
precedence is workspace variables > variable sets > HCL defaults, so with no
default a missing input fails loudly instead of quietly provisioning something
named `cell1 dev`. `cell_type` is additionally validated against the four
allowed values in HCL, and offered as `allowedValues` on the pipeline input.

`project_prefix` is not an input either — there is exactly one platform-wide
prefix, defined once in `modules/naming`.

### All three parts appear in every resource name

`cells/main.tf` derives `local.cell_id = "<cell>-<type>-<region>"` and passes
it to every module, so cell1/dev/us-east-1 produces
`toyota-full-cell1-dev-us-east-1-runtime-role` and so on.

This is required, not cosmetic:

- **region**, because IAM role names and S3 bucket names are *global*, so two
  regional instances of the same cell would collide on them
- **type**, so the dev and prod copies of a cell can coexist in one account

Regional resources (log groups, guardrails, gateways) carry both too, purely
so the naming is uniform and the next global resource someone adds is safe by
default.

Anything looking a cell role up by name has to build the same string.
`infra/runtime-dev`, `infra/runtime-prod` and `infra/tenant-agentic` each have
their own `cell_name` / `cell_type` variables plus
`data.aws_region.current`, and rebuild `local.cell_id` identically. Those
default to `cell1` / `dev`, i.e. they attach to the dev cell in whichever
region they deploy into — point the prod Runtime at `cell_type = "prod"` once
a prod cell exists in that region.

## The pipeline

`Provision Cell` (`provision_cell`), YAML in
`harness/pipelines/provision-cell.yaml`. Inputs: `cell_name`, `cell_type` and
`aws_connector`. Stages:

1. **Ensure Cell Workspaces** (CI) — for each region in `REGIONS`, creates the
   `<cell>_<type>_<region>` workspace if it does not already exist, pointed at
   `opentofu/cells` with that region's `AWS_DEFAULT_REGION`. Idempotent, so
   every run is safe.
2. **Provision us-east-1** (IaCM) — init → plan → approval → apply against
   `<cell>_<type>_us_east_1`.
3. **Provision us-west-2** (IaCM) — the same against `<cell>_<type>_us_west_2`.

Because stage 1 creates the workspaces, onboarding a cell needs no manual
setup in the UI and no helper script.

Harness validates the AWS connector when a workspace is **saved**, so
`provider_connector` cannot be a runtime expression. That is why
`aws_connector` is consumed at workspace-creation time; on later runs it must
match the connector already pinned to the workspace.

### Local runs

```bash
cd cells
AWS_DEFAULT_REGION=us-west-2 tofu plan -var cell_name=cell1 -var cell_type=dev
```

## Adding a cell, or an environment of a cell

Run `Provision Cell` with the new `cell_name` / `cell_type`. There is nothing
to copy and no directory to create: the bootstrap stage creates the two
regional workspaces, and the modules are already parameterized.

Note that changing `cell_name` or `cell_type` on an **existing** workspace
renames resources inside that workspace's state rather than creating a new
instance — a new instance is a new workspace, which is what the bootstrap
stage does.

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
- **Single `cells/` directory** — the per-cell `cells/cell1/` directory is
  gone; cell identity is a pipeline input, not a path.
- **`cell_type` added** — instances are `<cell>-<type>-<region>`, so a cell's
  dev/test/stage/prod copies coexist without name collisions.
