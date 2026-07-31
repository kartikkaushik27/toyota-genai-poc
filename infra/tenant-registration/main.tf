data "aws_caller_identity" "current" {}

locals {
  tenant = replace(lower(var.tenant_name), "/[^a-z0-9]/", "-")
}

# ── Per-tenant Bedrock Guardrail (sheet: "Create a Bedrock guardrail in Cell 1 for
#    each new tenant") — same content policy as the platform default, but a
#    dedicated resource per tenant so each can be tuned independently. ──
resource "aws_bedrock_guardrail" "tenant" {
  name                      = "${var.project_prefix}-${local.tenant}-guardrail"
  blocked_input_messaging   = "This request cannot be processed due to content policy."
  blocked_outputs_messaging = "This response cannot be shown due to content policy."

  content_policy_config {
    filters_config {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "INSULTS"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "MISCONDUCT"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
  }

  tags = { Project = "toyota-genai-full", Tenant = local.tenant }
}

# ── Per-tenant cross-account IAM role (sheet: "Create a cross-account IAM role and
#    policy in Cell 1 for each new tenant") ──
resource "aws_iam_role" "tenant_cross_account" {
  name = "${var.project_prefix}-${local.tenant}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = "toyota-genai-full", Tenant = local.tenant }
}

resource "aws_iam_role_policy" "tenant_cross_account_permissions" {
  name = "${var.project_prefix}-${local.tenant}-permissions"
  role = aws_iam_role.tenant_cross_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "TenantBedrockAccess"
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel", "bedrock:ApplyGuardrail"]
      Resource = "*"
    }]
  })
}

# ── Per-tenant CloudWatch log group (sheet: "Configure a CloudWatch log group in
#    Cell 1 for each new tenant") ──
resource "aws_cloudwatch_log_group" "tenant" {
  name              = "/${var.project_prefix}/tenant/${local.tenant}"
  retention_in_days = 14
  tags              = { Project = "toyota-genai-full", Tenant = local.tenant }
}

# ── Mark tenant Active in the registry (sheet: "Update the agentic tenant status
#    to Active in DynamoDB after provisioning completes") — native Terraform
#    resource instead of an `aws dynamodb put-item` CLI call. ──
resource "aws_dynamodb_table_item" "tenant_status" {
  table_name = "${var.project_prefix}-tenant-registry"
  hash_key   = "tenant_id"

  item = jsonencode({
    tenant_id    = { S = local.tenant }
    status       = { S = "Active" }
    guardrail_id = { S = aws_bedrock_guardrail.tenant.guardrail_id }
    iam_role_arn = { S = aws_iam_role.tenant_cross_account.arn }
    log_group    = { S = aws_cloudwatch_log_group.tenant.name }
  })
}

# NOTE — intentionally not built in this POC pass (documented as follow-ons):
#   * Optional Bedrock Knowledge Base + AOSS per tenant (sheet rows 17-19) — real
#     KB/AOSS provisioning needs an embeddings model choice and a data source,
#     which is a per-tenant business decision, not a generic infra default.
#   * Dynatrace OpenTelemetry integration (sheet row 14) — requires a live
#     Dynatrace tenant/API token this AWS account does not have.

output "tenant_guardrail_id" {
  value = aws_bedrock_guardrail.tenant.guardrail_id
}

output "tenant_role_arn" {
  value = aws_iam_role.tenant_cross_account.arn
}

output "tenant_log_group" {
  value = aws_cloudwatch_log_group.tenant.name
}
