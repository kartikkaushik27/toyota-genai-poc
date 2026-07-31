data "aws_caller_identity" "current" {}

# ── Bedrock enablement check (sheet: "Enable AWS Bedrock in the Cell 1 account") ──
# There is no explicit "enable" resource for Bedrock — access is granted at the
# account/model level. This data source proves the AWS credentials driving this
# workspace can already reach the Bedrock control plane, which is the practical
# definition of "enabled" for automation purposes.
data "aws_bedrock_foundation_models" "available" {}

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

# ── Cost analysis export bucket (sheet: "S3 bucket to receive CUR2.0 data exports") ──
resource "aws_s3_bucket" "cur_exports" {
  bucket = "${var.project_prefix}-cur-exports-${data.aws_caller_identity.current.account_id}"
  tags   = { Project = "toyota-genai-full", Purpose = "cost-analysis" }
}

resource "aws_s3_bucket_public_access_block" "cur_exports" {
  bucket                  = aws_s3_bucket.cur_exports.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
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

# ── Base IAM role for Cell 1 automation (sheet: "Create base IAM roles and policies in the Cell 1 account") ──
resource "aws_iam_role" "cell_base_automation" {
  name = "${var.project_prefix}-cell-base-automation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = "toyota-genai-full", Purpose = "cell-base-automation" }
}

# ── Cross-account IAM role: Model Gateway -> Bedrock routing in Cell 1 ──
# (sheet: "Create cross-account IAM roles and policies so the Model Gateway can
# route traffic to Bedrock in Cell 1" — flagged in requirements as "needs to be
# repeatable separately", so this is its own dedicated role, not reused from the
# AgentCore Runtime role.)
resource "aws_iam_role" "model_gateway_to_bedrock" {
  name = "${var.project_prefix}-model-gateway-bedrock-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = "toyota-genai-full", Purpose = "model-gateway-routing" }
}

resource "aws_iam_role_policy" "model_gateway_to_bedrock_permissions" {
  name = "${var.project_prefix}-model-gateway-bedrock-permissions"
  role = aws_iam_role.model_gateway_to_bedrock.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "BedrockRouting"
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:ListFoundationModels"]
      Resource = "*"
    }]
  })
}

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

# ── CloudWatch: admin + model gateway API debugging (sheet rows 9-10) ──
resource "aws_cloudwatch_log_group" "platform" {
  name              = "/${var.project_prefix}/platform"
  retention_in_days = 14
  tags              = { Project = "toyota-genai-full" }
}

# ── CloudWatch: Bedrock invocation logs for cost analysis (sheet row 11) ──
resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  name              = "/${var.project_prefix}/bedrock-invocations"
  retention_in_days = 14
  tags              = { Project = "toyota-genai-full", Purpose = "cost-and-debug-analysis" }
}

# ── CloudWatch dashboards (requirements row 22: "Set up cloudwatch dashboards. Cell account") ──
resource "aws_cloudwatch_dashboard" "platform_overview" {
  dashboard_name = "${var.project_prefix}-platform-overview"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "log"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.bedrock_invocations.name}' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          region = var.aws_region
          title  = "Recent Bedrock Invocations"
        }
      }
    ]
  })
}

output "tenant_registry_table" {
  value = aws_dynamodb_table.tenant_registry.name
}

output "cur_exports_bucket" {
  value = aws_s3_bucket.cur_exports.bucket
}

output "ecr_repository_url" {
  value = aws_ecr_repository.agent.repository_url
}

output "agentcore_runtime_role_arn" {
  value = aws_iam_role.agentcore_runtime.arn
}

output "model_gateway_role_arn" {
  value = aws_iam_role.model_gateway_to_bedrock.arn
}

output "platform_log_group" {
  value = aws_cloudwatch_log_group.platform.name
}

output "bedrock_models_available" {
  value = length(data.aws_bedrock_foundation_models.available.model_summaries)
}
