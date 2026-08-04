data "aws_caller_identity" "current" {}

# ── IAM role for the Gateway (sheet: "Create an IAM role for the Gateway with
#    the bedrock-agentcore.amazonaws.com service principal") ──
resource "aws_iam_role" "gateway" {
  name = "${var.project_prefix}-${var.cell_name}-gateway-role"

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

  tags = { Project = "toyota-genai-full", Cell = var.cell_name, Purpose = "gateway" }
}

resource "aws_iam_role_policy" "gateway_permissions" {
  name = "${var.project_prefix}-${var.cell_name}-gateway-permissions"
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
        # Per AWS docs (policy-permissions.html): the Gateway's execution role
        # needs GetPolicyEngine, AuthorizeAction, and PartiallyAuthorizeActions
        # on both the policy-engine and gateway ARNs, or every tool invocation
        # silently default-denies even with permit policies in place.
        Sid      = "PolicyEngineAccess"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:GetPolicyEngine", "bedrock-agentcore:GetPolicy", "bedrock-agentcore:ListPolicies", "bedrock-agentcore:AuthorizeAction", "bedrock-agentcore:PartiallyAuthorizeActions"]
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

# ── CloudWatch log group for the Gateway ──
resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/aws/bedrock/agentcore/gateway/${var.project_prefix}-${var.cell_name}"
  retention_in_days = 14
  tags              = { Project = "toyota-genai-full", Cell = var.cell_name }
}

# ── AgentCore Gateway (sheet: "Deploy the Agentcore Gateway in Cell 1 with
#    either CUSTOM_JWT or AWS_IAM authorization", "Set the Gateway protocol
#    type", "Associate the Policy Engine ARN with the Gateway and configure
#    enforcement mode") — Cell Provisioning.
#
#    CHANGED: switched from CUSTOM_JWT to AWS_IAM. CUSTOM_JWT required
#    standing up a whole Cognito User Pool + client + resource server purely
#    to give AWS a real, reachable OIDC discovery URL (AWS validates the
#    discovery document at Gateway-creation time, so a placeholder URL always
#    failed). AWS_IAM needs none of that: callers authenticate with a normal
#    SigV4-signed AWS request and just need `bedrock-agentcore:InvokeGateway`
#    on this Gateway's ARN (granted as a glue policy in cells/<cell>/main.tf,
#    since it needs both this module's and the runtime-iam module's outputs).
#
#    Requires AWS provider >= 6.19.0 — `authorizer_configuration` only became
#    optional for AWS_IAM in that release; before it, the provider rejected
#    omitting the block even though the underlying AWS API never required it
#    for AWS_IAM. See opentofu/cells/cell1/backend.tf. ──
resource "aws_bedrockagentcore_gateway" "cell" {
  name        = "${var.project_prefix}-${var.cell_name}-gateway"
  description = "${var.cell_name} Gateway — converts tenant tools (Lambda/API/Runtime) into MCP-compatible targets"
  role_arn    = aws_iam_role.gateway.arn

  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"

  # Deployment-order enforcement (sheet: "Enforce the deployment order: Policy
  # Engine then Gateway then Runtime"). OpenTofu will not create the Gateway
  # until the Policy Engine exists, because policy_engine_configuration below
  # references its ARN directly (passed in as var.policy_engine_arn from the
  # policy-engine module's output).
  policy_engine_configuration {
    arn  = var.policy_engine_arn
    mode = "LOG_ONLY" # LOG_ONLY for the POC so a bad policy can't lock out every tool call
  }

  depends_on = [time_sleep.gateway_iam_propagation]

  tags = { Project = "toyota-genai-full", Cell = var.cell_name }
}

# IAM is eventually consistent — the AuthorizeAction/PartiallyAuthorizeActions
# permissions the Gateway needs on the Policy Engine can take longer to
# propagate than the immediate next API call. This gives it a fixed buffer
# instead of failing intermittently.
resource "time_sleep" "gateway_iam_propagation" {
  depends_on      = [aws_iam_role_policy.gateway_permissions]
  create_duration = "45s"
}
