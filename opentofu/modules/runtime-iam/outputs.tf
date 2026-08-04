output "runtime_role_arn" {
  value = aws_iam_role.runtime_cell.arn
}

output "runtime_role_id" {
  description = "IAM role name/id for the Runtime role — used by cells/<cell>/main.tf to attach the glue policy granting bedrock-agentcore:InvokeGateway."
  value       = aws_iam_role.runtime_cell.id
}

output "runtime_log_group" {
  value = aws_cloudwatch_log_group.runtime.name
}

output "application_log_group" {
  value = aws_cloudwatch_log_group.application.name
}

output "bedrock_invocations_log_group" {
  value = aws_cloudwatch_log_group.bedrock_invocations.name
}
