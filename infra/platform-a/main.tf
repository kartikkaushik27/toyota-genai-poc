data "aws_caller_identity" "current" {}

# NOTE — Bedrock enablement check, the CUR2.0 S3 bucket, and the two
# CloudWatch log groups that used to live in this file have all been
# RELOCATED to opentofu/cells/cell1 (see opentofu/README.md) as part of the
# Cell Provisioning restructuring — they're Cell Provisioning concerns, not
# platform-account concerns, and the S3 bucket is now created per-cell
# instead of once globally. This file keeps only the genuinely
# platform-account-wide resources.

# ── DynamoDB tables (sheet: "Deploy Dynamodb 3 count: tenant config, cost, tenant registration") ──
resource "aws_dynamodb_table" "tenant_registry" {
  name         = "${var.project_prefix}-tenant-registry"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "tenant_id"

  attribute {
    name = "tenant_id"
    type = "S"
  }

  tags = { Project = "toyota-genai-full", Purpose = "tenant-registration" }
}

resource "aws_dynamodb_table" "tenant_config" {
  name         = "${var.project_prefix}-tenant-config"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "tenant_id"

  attribute {
    name = "tenant_id"
    type = "S"
  }

  tags = { Project = "toyota-genai-full", Purpose = "tenant-config" }
}

resource "aws_dynamodb_table" "cost_tracking" {
  name         = "${var.project_prefix}-cost-tracking"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "tenant_id"
  range_key    = "period"

  attribute {
    name = "tenant_id"
    type = "S"
  }
  attribute {
    name = "period"
    type = "S"
  }

  tags = { Project = "toyota-genai-full", Purpose = "cost-analysis" }
}

# ── SecretsManager in Platform account (requirements: "Need SecretsManager in Platform account") ──
resource "aws_secretsmanager_secret" "platform_config" {
  name        = "${var.project_prefix}-platform-config"
  description = "Central platform configuration secret (model gateway routing keys, shared config)"
  tags        = { Project = "toyota-genai-full" }
}

resource "aws_secretsmanager_secret_version" "platform_config" {
  secret_id = aws_secretsmanager_secret.platform_config.id
  secret_string = jsonencode({
    provisioned_by = "harness-iacm"
    purpose        = "placeholder for model gateway + admin backend shared config"
  })
}

# ── Container registry for the agent runtime image ──
resource "aws_ecr_repository" "agent" {
  name                 = "${var.project_prefix}-agent"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = "toyota-genai-full" }
}

# NOTE — the base Cell-1-automation IAM role and the cross-account
# Model-Gateway-to-Bedrock IAM role that used to live here have been
# RELOCATED to infra/tenant-registration/main.tf. Per the updated
# requirement categorization, both are tagged "Tenant Onboarding" rather
# than "Cell Provisioning" — see the comments there for the moved resources.

# ── IAM execution role for the AgentCore Runtime ──
resource "aws_iam_role" "agentcore_runtime" {
  name = "${var.project_prefix}-agentcore-runtime-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = { Project = "toyota-genai-full" }
}

resource "aws_iam_role_policy" "agentcore_runtime_permissions" {
  name = "${var.project_prefix}-agentcore-runtime-permissions"
  role = aws_iam_role.agentcore_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BedrockInvoke"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:ApplyGuardrail"]
        Resource = "*"
      },
      {
        Sid      = "Logging"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = "*"
      },
      {
        Sid      = "Tracing"
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      },
      {
        Sid      = "ECRPull"
        Effect   = "Allow"
        Action   = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability", "ecr:GetAuthorizationToken"]
        Resource = "*"
      }
    ]
  })
}

# NOTE — the "platform" admin/Model-Gateway-API-debug log group, the
# "bedrock_invocations" log group, and the CloudWatch dashboard that read
# from it have all been RELOCATED to opentofu/cells/cell1 (see
# opentofu/README.md) — they're Cell Provisioning concerns. A per-cell
# dashboard is a natural next addition to opentofu/modules/cell-observability
# once more than one cell exists to compare.

output "tenant_registry_table" {
  value = aws_dynamodb_table.tenant_registry.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.agent.repository_url
}

output "agentcore_runtime_role_arn" {
  value = aws_iam_role.agentcore_runtime.arn
}
