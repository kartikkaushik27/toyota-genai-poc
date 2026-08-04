data "aws_ecr_repository" "agent" {
  name = "${var.project_prefix}-agent"
}

# The cell's IAM role names now carry the region, because a cell is
# provisioned once per region and IAM is a global namespace. This picks up
# the cell instance living in the same region this Runtime deploys into.
data "aws_region" "current" {}

locals {
  # Must match local.cell_id in opentofu/cells/main.tf.
  cell_id = "${var.cell_name}-${var.cell_type}-${data.aws_region.current.region}"
}

data "aws_iam_role" "runtime" {
  name = "${var.project_prefix}-${local.cell_id}-runtime-role"
}

# ── AgentCore Runtime, Dev (sheet: "Deploy the Agentcore Runtime as a container in
#    Cell 1 using the ECR container URI" — confirmed "Natively supported - CD").
#    This replaces the CLI create/update script used in the original POC with the
#    native aws_bedrockagentcore_agent_runtime Terraform resource, now that the
#    AWS provider ships one. ──
resource "aws_bedrockagentcore_agent_runtime" "dev" {
  agent_runtime_name = "${replace(var.project_prefix, "-", "_")}_agent_dev"
  description        = "Dev AgentCore Runtime for the Toyota GenAI agent"
  role_arn           = data.aws_iam_role.runtime.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${data.aws_ecr_repository.agent.repository_url}:${var.image_tag}"
    }
  }

  environment_variables = {
    BEDROCK_MODEL_ID = "anthropic.claude-3-haiku-20240307-v1:0"
  }

  network_configuration {
    network_mode = "PUBLIC"
  }
}

output "agent_runtime_arn" {
  value = aws_bedrockagentcore_agent_runtime.dev.agent_runtime_arn
}

output "agent_runtime_id" {
  value = aws_bedrockagentcore_agent_runtime.dev.agent_runtime_id
}
