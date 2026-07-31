data "aws_caller_identity" "current" {}

locals {
  tenant = replace(lower(var.tenant_name), "/[^a-z0-9]/", "-")
}

data "aws_iam_role" "gateway" {
  name = "${var.project_prefix}-gateway-role"
}

# ── Per-tenant cross-account IAM role in Cell 1 (sheet: "Create a cross-account
#    IAM role in Cell 1 for each agentic tenant") ──
resource "aws_iam_role" "tenant_agentic" {
  name = "${var.project_prefix}-${local.tenant}-agentic-role"

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

# ── Tenant's MCP tool Lambda (stand-in for real business logic) ──
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_prefix}-${local.tenant}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "tenant_tool" {
  filename         = "${path.module}/tenant_tool.zip"
  source_code_hash = filebase64sha256("${path.module}/tenant_tool.zip")
  function_name    = "${var.project_prefix}-${local.tenant}-mcp-tool"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.handler"
  runtime          = "python3.12"

  tags = { Project = "toyota-genai-full", Tenant = local.tenant }
}

# ── Grant bedrock-agentcore.amazonaws.com permission to invoke the Lambda
#    (sheet: "Grant aws_lambda_permission to the bedrock-agentcore.amazonaws.com
#    principal for Lambda MCP targets") ──
resource "aws_lambda_permission" "allow_agentcore" {
  statement_id  = "AllowAgentCoreInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tenant_tool.function_name
  principal     = "bedrock-agentcore.amazonaws.com"
}

# ── Inline lambda:InvokeFunction policy on the Gateway role (sheet: "Attach an
#    inline lambda:InvokeFunction policy to the Gateway role for Lambda MCP
#    targets") — attaches to the shared Gateway role from infra/platform-b-cell,
#    scoped to just this tenant's Lambda ARN. ──
resource "aws_iam_role_policy" "gateway_invoke_tenant_lambda" {
  name = "${var.project_prefix}-${local.tenant}-gateway-lambda-invoke"
  role = data.aws_iam_role.gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.tenant_tool.arn
    }]
  })
}

# ── Gateway Target: Lambda MCP Tool (sheet: "Register gateway targets of type
#    Lambda MCP Tool with tool name, description, and input schema") ──
resource "aws_bedrockagentcore_gateway_target" "tenant_lambda_tool" {
  name               = "${local.tenant}-lambda-tool"
  gateway_identifier = var.gateway_id
  description        = "Tenant ${local.tenant} business-logic tool, exposed via MCP"

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.tenant_tool.arn

        tool_schema {
          inline_payload {
            name        = "${local.tenant}_echo_tool"
            description = "Echoes the input back — placeholder for tenant ${local.tenant}'s real tool"

            input_schema {
              type        = "object"
              description = "Tool input"

              property {
                name        = "message"
                type        = "string"
                description = "Message to process"
                required    = true
              }
            }
          }
        }
      }
    }
  }

  depends_on = [aws_lambda_permission.allow_agentcore, aws_iam_role_policy.gateway_invoke_tenant_lambda]
}

# ── Gateway Target: Remote MCP Server (sheet: "Register gateway targets of type
#    Remote MCP Server with endpoint URL and listing mode", "Configure the
#    credential provider with gateway_iam_role and SigV4 for Remote MCP Server
#    targets") — demonstrative target pointing at a placeholder endpoint; real
#    tenants would supply their own MCP server URL here. ──
resource "aws_bedrockagentcore_gateway_target" "tenant_remote_mcp" {
  name               = "${local.tenant}-remote-mcp"
  gateway_identifier = var.gateway_id
  description        = "Placeholder remote MCP server target for tenant ${local.tenant}"

  credential_provider_configuration {
    gateway_iam_role {
      service = "bedrock-agentcore"
    }
  }

  target_configuration {
    mcp {
      mcp_server {
        endpoint     = "https://${local.tenant}-mcp.example.com/mcp"
        listing_mode = "DEFAULT"
      }
    }
  }
}

# NOTE — HTTP Runtime target (sheet: "Register gateway targets of type HTTP
# Runtime with runtime ARN and qualifier", "Set the SigV4 service to
# bedrock-agentcore for HTTP Runtime targets") is intentionally not created
# here: it needs the agent_runtime_arn produced by infra/runtime-dev, which
# is applied later in the Agent CD Deploy pipeline — a genuine cross-workspace
# ordering dependency to wire up once IaCM output-passing is used end-to-end.
# The resource shape is:
#
# resource "aws_bedrockagentcore_gateway_target" "tenant_runtime" {
#   name               = "${local.tenant}-runtime"
#   gateway_identifier = var.gateway_id
#   credential_provider_configuration {
#     gateway_iam_role { service = "bedrock-agentcore" }
#   }
#   target_configuration {
#     http {
#       agentcore_runtime {
#         arn       = <runtime-dev workspace output: agent_runtime_arn>
#         qualifier = "DEFAULT"
#       }
#     }
#   }
# }

# ── Per-tenant Cedar policy (sheet: "Create Cedar policies with permit and forbid
#    rules in the Policy Engine for each tenant") — AWS validates that the
#    `resource` slot is constrained to a specific AgentCore::Gateway resource or
#    the AgentCore::Gateway resource type (wildcard resources are rejected), and
#    separately rejects any `permit` where principal + action + resource are ALL
#    unconstrained ("Overly Permissive"). So this scopes the permit to the one
#    principal that should be allowed through: this tenant's own cross-account
#    IAM role. ──
resource "aws_bedrockagentcore_policy" "tenant_permit" {
  name             = "${replace(local.tenant, "-", "_")}_permit_tools"
  policy_engine_id = var.policy_engine_id
  description      = "Permit tenant ${local.tenant}'s own IAM role to call tools exposed through the Cell 1 Gateway"

  definition {
    cedar {
      statement = <<-EOT
        permit(
          principal == AgentCore::IamEntity::"${aws_iam_role.tenant_agentic.arn}",
          action,
          resource is AgentCore::Gateway
        );
      EOT
    }
  }

  depends_on = [aws_iam_role.tenant_agentic]
}

resource "aws_bedrockagentcore_policy" "tenant_forbid_others" {
  name             = "${replace(local.tenant, "-", "_")}_forbid_delete_tools"
  policy_engine_id = var.policy_engine_id
  description      = "Forbid tenant ${local.tenant} from invoking any tool whose name suggests a delete operation"

  # Every tool call through the Gateway maps to the single action
  # AgentCore::Action::"Mcp" — there's no per-verb (Read/Write/Delete) action
  # namespace, so "forbid" rules have to key off the `context.toolName` that
  # the Gateway injects at runtime rather than the `action` slot itself.
  definition {
    cedar {
      statement = <<-EOT
        forbid(principal, action, resource is AgentCore::Gateway)
        when { context has toolName && context.toolName like "*delete*" };
      EOT
    }
  }
}

# ── AgentCore Memory in the Tenant Account, not Cell 1 (sheet: "Provision
#    Agentcore Memory in the Tenant Account, not in Cell 1", "Create a Memory IAM
#    execution role with the AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy",
#    "Configure event expiry duration between 7 and 365 days") ──
resource "aws_iam_role" "memory_exec" {
  name = "${var.project_prefix}-${local.tenant}-memory-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "memory_exec_policy" {
  role       = aws_iam_role.memory_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy"
}

resource "aws_bedrockagentcore_memory" "tenant" {
  name                      = "${replace(var.project_prefix, "-", "_")}_${replace(local.tenant, "-", "_")}_memory"
  description               = "Conversation + context memory for tenant ${local.tenant}"
  event_expiry_duration     = 30
  memory_execution_role_arn = aws_iam_role.memory_exec.arn

  depends_on = [aws_iam_role_policy_attachment.memory_exec_policy]
}

# ── Memory Strategy: SEMANTIC (sheet: "Optionally create a SEMANTIC memory
#    strategy with namespaces") — proof point; SUMMARIZATION, USER_PREFERENCE,
#    and EPISODIC follow the same shape with type changed. ──
resource "aws_bedrockagentcore_memory_strategy" "tenant_semantic" {
  name                = "${replace(local.tenant, "-", "_")}_semantic"
  memory_id           = aws_bedrockagentcore_memory.tenant.id
  type                = "SEMANTIC"
  namespace_templates = ["${local.tenant}/facts"]
}

output "tenant_agentic_role_arn" {
  value = aws_iam_role.tenant_agentic.arn
}

output "tenant_lambda_arn" {
  value = aws_lambda_function.tenant_tool.arn
}

output "tenant_memory_id" {
  value = aws_bedrockagentcore_memory.tenant.id
}
