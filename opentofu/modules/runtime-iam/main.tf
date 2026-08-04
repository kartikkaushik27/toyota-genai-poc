data "aws_caller_identity" "current" {}

# ── IAM role for the Runtime, full permission set (sheet: "Create an IAM role
#    for the Runtime with bedrock/guardrail/logs/metrics/X-Ray permissions") ──
resource "aws_iam_role" "runtime_cell" {
  name = "${var.project_prefix}-${var.cell_name}-runtime-role"

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

  tags = { Project = "toyota-genai-full", Cell = var.cell_name, Purpose = "runtime" }
}

resource "aws_iam_role_policy" "runtime_cell_permissions" {
  name = "${var.project_prefix}-${var.cell_name}-runtime-permissions"
  role = aws_iam_role.runtime_cell.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BedrockInvokeAndGuardrail"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:ApplyGuardrail"]
        Resource = "*"
      },
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = "*"
      },
      {
        Sid      = "CloudWatchMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        Sid      = "XRay"
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      },
      {
        # AgentCore validates it can pull the container image from ECR at
        # Runtime-creation time using this role's credentials.
        Sid      = "EcrPull"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = "*"
      }
    ]
  })
}

# ── CloudWatch log groups for Runtime + Application logs ──
resource "aws_cloudwatch_log_group" "runtime" {
  name              = "/${var.project_prefix}/${var.cell_name}/runtime"
  retention_in_days = 14
  tags              = { Project = "toyota-genai-full", Cell = var.cell_name }
}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/${var.project_prefix}/${var.cell_name}/application"
  retention_in_days = 14
  tags              = { Project = "toyota-genai-full", Cell = var.cell_name }
}

# ── Bedrock model invocation logging — account+region singleton per cell
#    (sheet: "Set up CloudWatch Bedrock Invocation logs in Cell 1 for platform
#    admin and tenant debugging", "Set up Bedrock invocation logs in Cell 1
#    for cost analysis") — Cell Provisioning. ──
resource "aws_iam_role" "invocation_logging" {
  name = "${var.project_prefix}-${var.cell_name}-invocation-logging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "invocation_logging_permissions" {
  name = "${var.project_prefix}-${var.cell_name}-invocation-logging-permissions"
  role = aws_iam_role.invocation_logging.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  name              = "/${var.project_prefix}/${var.cell_name}/bedrock-invocations"
  retention_in_days = 14
  tags              = { Project = "toyota-genai-full", Cell = var.cell_name, Purpose = "cost-and-debug-analysis" }
}

resource "aws_bedrock_model_invocation_logging_configuration" "cell" {
  logging_config {
    text_data_delivery_enabled = true
    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_invocations.name
      role_arn       = aws_iam_role.invocation_logging.arn
    }
  }

  depends_on = [aws_iam_role_policy.invocation_logging_permissions]
}
