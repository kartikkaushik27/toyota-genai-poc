# ═══════════════════════════════════════════════════════════════════════════
# Cell 1 — composition root.
#
# This file's only job is to wire the reusable component modules together in
# the right order for THIS cell. It is region-agnostic: the provision-cell
# pipeline runs it once per region, each from its own Harness workspace, and
# the region only reaches the code through AWS_DEFAULT_REGION.
#
# Adding a new cell (e.g. Cell 2) means copying this directory to cells/cell2/
# and running the pipeline with cell_name=cell2 — no module changes, no
# per-region files.
# ═══════════════════════════════════════════════════════════════════════════

# ── Platform-wide naming prefix. Defined once in modules/naming and shared
#    by every cell, so it is NOT a per-cell pipeline input. ──
module "naming" {
  source = "../../modules/naming"
}

data "aws_region" "current" {}

locals {
  project_prefix = module.naming.project_prefix

  # A cell exists once per region, and each instance is provisioned from its
  # own workspace/state. The region therefore has to be part of the name:
  # IAM roles and S3 bucket names are global, so cell1 in us-east-1 and cell1
  # in us-west-2 would collide on those without it. Everything downstream is
  # named from this, which keeps regional and global resources consistent
  # rather than only suffixing the ones that strictly need it.
  cell_id = "${var.cell_name}-${data.aws_region.current.region}"
}

# ── Cell Provisioning: Bedrock enablement check ──
module "bedrock_enablement" {
  source = "../../modules/bedrock-enablement"
}

# ── Cell Provisioning: admin + Model Gateway API debug logs ──
module "cell_observability" {
  source         = "../../modules/cell-observability"
  project_prefix = local.project_prefix
  cell_name      = local.cell_id
}

# ── Cell Provisioning: per-cell CUR2.0 cost-export S3 bucket ──
module "cell_cost" {
  source         = "../../modules/cell-cost"
  project_prefix = local.project_prefix
  cell_name      = local.cell_id
}

# ── Cell Provisioning: Runtime IAM role + Runtime/Application logs +
#    Bedrock invocation logging (cost + debug analysis) ──
module "runtime_iam" {
  source         = "../../modules/runtime-iam"
  project_prefix = local.project_prefix
  cell_name      = local.cell_id
}

# ── Cell Provisioning: KMS-encrypted Policy Engine + baseline Cedar policy.
#    Needs the Runtime role's ARN so the baseline permit statement can scope
#    itself to that one principal instead of being overly permissive. ──
module "policy_engine" {
  source           = "../../modules/policy-engine"
  project_prefix   = local.project_prefix
  cell_name        = local.cell_id
  runtime_role_arn = module.runtime_iam.runtime_role_arn
}

# ── Cell Provisioning: Gateway (AWS_IAM authorizer, no Cognito). Needs the
#    Policy Engine's ARN so deployment order (Policy Engine -> Gateway) is
#    enforced by OpenTofu's own dependency graph. ──
module "gateway" {
  source                    = "../../modules/gateway"
  project_prefix            = local.project_prefix
  cell_name                 = local.cell_id
  policy_engine_arn         = module.policy_engine.policy_engine_arn
  policy_engine_kms_key_arn = module.policy_engine.kms_key_arn
}

# ── Cell Provisioning: default Guardrail ──
module "guardrail" {
  source         = "../../modules/guardrail"
  project_prefix = local.project_prefix
  cell_name      = local.cell_id
}

# ── Glue: let the Runtime actually call through the Gateway.
#    With authorizer_type = AWS_IAM, every caller needs
#    bedrock-agentcore:InvokeGateway scoped to this specific Gateway's ARN.
#    This lives here (not inside either module) because it's the one
#    resource that genuinely depends on outputs from BOTH the runtime-iam
#    module and the gateway module. ──
resource "aws_iam_role_policy" "runtime_invoke_gateway" {
  name = "${local.project_prefix}-${local.cell_id}-runtime-invoke-gateway"
  role = module.runtime_iam.runtime_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeGateway"
      Effect   = "Allow"
      Action   = "bedrock-agentcore:InvokeGateway"
      Resource = module.gateway.gateway_arn
    }]
  })
}
