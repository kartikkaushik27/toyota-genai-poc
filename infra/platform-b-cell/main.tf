data "aws_caller_identity" "current" {}

# ── Policy Engine (sheet: "Deploy the Agentcore Policy Engine in Cell 1 before the Gateway") ──
resource "aws_bedrockagentcore_policy_engine" "cell1" {
  name        = "${replace(var.project_prefix, "-", "_")}_cell1_policy_engine"
  description = "Cedar policy engine for GenAI Platform Cell 1 — evaluates every tool call made through the Gateway"
}

# ── Baseline Cedar policy (sheet: "Create Cedar policies with permit and forbid rules") ──
# This is the platform-wide default; per-tenant permit/forbid rules are added in
# infra/tenant-agentic (kept separate so tenant policies don't require re-applying
# this workspace on every onboarding).
#
# AWS's policy analyzer rejects any statement where principal, action, AND
# resource are all unconstrained ("Overly Permissive: will allow every request
# for ... Any Future Tools ... if the policy is added") — so a blanket
# permit-all isn't just bad practice here, it's a hard validation error. This
# scopes the permit to the one principal that legitimately calls through the
# Gateway on tenants' behalf: the AgentCore Runtime's own execution role.
resource "aws_bedrockagentcore_policy" "default_permit" {
  name             = "default_permit_runtime_tools"
  policy_engine_id = aws_bedrockagentcore_policy_engine.cell1.policy_engine_id
  description      = "Permit the Cell 1 Runtime's execution role to call any tool through the Gateway"

  definition {
    cedar {
      statement = <<-EOT
        permit(
          principal == AgentCore::IamEntity::"${aws_iam_role.runtime_cell.arn}",
          action,
          resource is AgentCore::Gateway
        );
      EOT
    }
  }

  depends_on = [aws_iam_role.runtime_cell]
}

# ── IAM role for the Gateway (sheet: "Create an IAM role for the Gateway with the
#    bedrock-agentcore.amazonaws.com service principal") ──
resource "aws_iam_role" "gateway" {
  name = "${var.project_prefix}-gateway-role"

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

  tags = { Project = "toyota-genai-full", Purpose = "gateway" }
}

resource "aws_iam_role_policy" "gateway_permissions" {
  name = "${var.project_prefix}-gateway-permissions"
  role = aws_iam_role.gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeTargets"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction", "bedrock-agentcore:InvokeAgentRuntime"]
        Resource = "*"
      },
      {
        Sid      = "PolicyEngineAccess"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:GetPolicyEngine", "bedrock-agentcore:GetPolicy", "bedrock-agentcore:ListPolicies"]
        Resource = "*"
      },
      {
        Sid      = "Logging"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

# ── CloudWatch log group for the Gateway (sheet: "/aws/bedrock/agentcore/gateway/*") ──
resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/aws/bedrock/agentcore/gateway/${var.project_prefix}"
  retention_in_days = 14
  tags              = { Project = "toyota-genai-full" }
}

# ── AgentCore Gateway (sheet: "Deploy the Agentcore Gateway in Cell 1 with either
#    CUSTOM_JWT or AWS_IAM authorization", "Configure the Gateway OIDC discovery URL,
#    allowed audiences, and allowed clients", "Set the Gateway protocol type",
#    "Associate the Policy Engine ARN with the Gateway and configure enforcement mode") ──
resource "aws_bedrockagentcore_gateway" "cell1" {
  name        = "${var.project_prefix}-cell1-gateway"
  description = "Cell 1 Gateway — converts tenant tools (Lambda/API/Runtime) into MCP-compatible targets"
  role_arn    = aws_iam_role.gateway.arn

  authorizer_type = "CUSTOM_JWT"
  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url    = "https://cognito-idp.${var.aws_region}.amazonaws.com/${var.project_prefix}-pool/.well-known/openid-configuration"
      allowed_audience = ["${var.project_prefix}-tenant-app"]
      allowed_clients  = ["${var.project_prefix}-tenant-client"]
    }
  }

  protocol_type = "MCP"

  # Deployment-order enforcement (sheet: "Enforce the deployment order: Policy Engine
  # then Gateway then Runtime" — confirmed "yes natively supported"). Terraform will
  # not create the Gateway until the Policy Engine + policy exist, because the
  # policy_engine_configuration block below references their IDs directly.
  policy_engine_configuration {
    arn  = aws_bedrockagentcore_policy_engine.cell1.policy_engine_arn
    mode = "LOG_ONLY" # LOG_ONLY for the POC so a bad policy can't lock out every tool call
  }

  depends_on = [aws_bedrockagentcore_policy.default_permit, aws_iam_role_policy.gateway_permissions]

  tags = { Project = "toyota-genai-full" }
}

# ── Platform-level default Guardrail, used to populate BEDROCK_GUARDRAIL_ID/VERSION
#    env vars on the Runtime (sheet row 33). Per-tenant guardrails are created in
#    infra/tenant-registration and override this at the tenant level. ──
resource "aws_bedrock_guardrail" "cell1_default" {
  name                      = "${var.project_prefix}-cell1-default-guardrail"
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
  }

  tags = { Project = "toyota-genai-full" }
}

# ── IAM role for the Runtime, full permission set per sheet row 34 ──
resource "aws_iam_role" "runtime_cell" {
  name = "${var.project_prefix}-cell1-runtime-role"

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

  tags = { Project = "toyota-genai-full", Purpose = "cell1-runtime" }
}

resource "aws_iam_role_policy" "runtime_cell_permissions" {
  name = "${var.project_prefix}-cell1-runtime-permissions"
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
      }
    ]
  })
}

# ── CloudWatch log groups for Runtime + Application logs (sheet row 35) ──
resource "aws_cloudwatch_log_group" "runtime" {
  name              = "/${var.project_prefix}/cell1/runtime"
  retention_in_days = 14
  tags              = { Project = "toyota-genai-full" }
}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/${var.project_prefix}/cell1/application"
  retention_in_days = 14
  tags              = { Project = "toyota-genai-full" }
}

# ── Bedrock model invocation logging — account+region singleton (requirements:
#    "Set up bedrock invocation logs for cost analysis") ──
resource "aws_iam_role" "invocation_logging" {
  name = "${var.project_prefix}-invocation-logging-role"

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
  name = "${var.project_prefix}-invocation-logging-permissions"
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

resource "aws_bedrock_model_invocation_logging_configuration" "cell1" {
  logging_config {
    text_data_delivery_enabled = true
    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_invocations.name
      role_arn       = aws_iam_role.invocation_logging.arn
    }
  }

  depends_on = [aws_iam_role_policy.invocation_logging_permissions]
}

resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  name              = "/${var.project_prefix}/cell1/bedrock-invocations"
  retention_in_days = 14
  tags              = { Project = "toyota-genai-full", Purpose = "cost-and-debug-analysis" }
}

output "policy_engine_arn" {
  value = aws_bedrockagentcore_policy_engine.cell1.policy_engine_arn
}

output "gateway_id" {
  value = aws_bedrockagentcore_gateway.cell1.gateway_id
}

output "gateway_arn" {
  value = aws_bedrockagentcore_gateway.cell1.gateway_arn
}

output "gateway_role_arn" {
  value = aws_iam_role.gateway.arn
}

output "runtime_role_arn" {
  value = aws_iam_role.runtime_cell.arn
}

output "default_guardrail_id" {
  value = aws_bedrock_guardrail.cell1_default.guardrail_id
}

output "default_guardrail_version" {
  value = aws_bedrock_guardrail.cell1_default.version
}
