data "aws_caller_identity" "current" {}

# ── Tenant Registry (mirrors "Non-Agentic/Agentic Tenant Onboarding" DynamoDB requirement) ──
resource "aws_dynamodb_table" "tenant_registry" {
  name         = "${var.project_prefix}-tenant-registry"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "tenant_id"

  attribute {
    name = "tenant_id"
    type = "S"
  }

  tags = {
    Project = "toyota-genai-poc"
    Purpose = "tenant-registry"
  }
}

# ── Cost analysis export bucket (mirrors "S3 bucket to receive CUR2.0 data exports" requirement) ──
resource "aws_s3_bucket" "cur_exports" {
  bucket = "${var.project_prefix}-cur-exports-${data.aws_caller_identity.current.account_id}"

  tags = {
    Project = "toyota-genai-poc"
    Purpose = "cost-analysis"
  }
}

resource "aws_s3_bucket_public_access_block" "cur_exports" {
  bucket                  = aws_s3_bucket.cur_exports.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ── Platform observability (mirrors "CloudWatch logs for admin/model gateway API debugging" requirement) ──
resource "aws_cloudwatch_log_group" "platform" {
  name              = "/${var.project_prefix}/platform"
  retention_in_days = 14

  tags = {
    Project = "toyota-genai-poc"
  }
}

resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  name              = "/${var.project_prefix}/bedrock-invocations"
  retention_in_days = 14

  tags = {
    Project = "toyota-genai-poc"
    Purpose = "cost-and-debug-analysis"
  }
}

# ── Container registry for the agent runtime image (mirrors "Build agent container image, push to ECR") ──
resource "aws_ecr_repository" "agent" {
  name                 = "${var.project_prefix}-agent"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = "toyota-genai-poc"
  }
}

# ── IAM execution role for the AgentCore Runtime (mirrors "Create IAM role for the Runtime" requirement) ──
resource "aws_iam_role" "agentcore_runtime" {
  name = "${var.project_prefix}-agentcore-runtime-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "bedrock-agentcore.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = {
    Project = "toyota-genai-poc"
  }
}

resource "aws_iam_role_policy" "agentcore_runtime_permissions" {
  name = "${var.project_prefix}-agentcore-runtime-permissions"
  role = aws_iam_role.agentcore_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ApplyGuardrail"
        ]
        Resource = "*"
      },
      {
        Sid    = "Logging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Sid    = "Tracing"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── Base IAM role Harness/pipelines assume for tenant + cell provisioning ──
resource "aws_iam_role" "platform_automation" {
  name = "${var.project_prefix}-platform-automation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = "toyota-genai-poc"
    Purpose = "cross-account-simulation"
  }
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

output "platform_log_group" {
  value = aws_cloudwatch_log_group.platform.name
}
