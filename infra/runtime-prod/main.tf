data "aws_ecr_repository" "agent" {
  name = "${var.project_prefix}-agent"
}

data "aws_iam_role" "runtime" {
  name = "${var.project_prefix}-cell1-runtime-role"
}

resource "aws_bedrockagentcore_agent_runtime" "prod" {
  agent_runtime_name = "${replace(var.project_prefix, "-", "_")}_agent_prod"
  description         = "Prod AgentCore Runtime for the Toyota GenAI agent"
  role_arn            = data.aws_iam_role.runtime.arn

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
  value = aws_bedrockagentcore_agent_runtime.prod.agent_runtime_arn
}

output "agent_runtime_id" {
  value = aws_bedrockagentcore_agent_runtime.prod.agent_runtime_id
}
