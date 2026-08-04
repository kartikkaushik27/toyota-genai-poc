output "policy_engine_arn" {
  value = aws_bedrockagentcore_policy_engine.cell.policy_engine_arn
}

output "policy_engine_id" {
  value = aws_bedrockagentcore_policy_engine.cell.policy_engine_id
}

output "kms_key_arn" {
  value = aws_kms_key.policy_engine.arn
}
