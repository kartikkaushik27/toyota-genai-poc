output "gateway_id" {
  value = aws_bedrockagentcore_gateway.cell.gateway_id
}

output "gateway_arn" {
  value = aws_bedrockagentcore_gateway.cell.gateway_arn
}

output "gateway_role_arn" {
  value = aws_iam_role.gateway.arn
}
