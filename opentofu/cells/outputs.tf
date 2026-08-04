# Makes it obvious from the run log which instance of the cell you are looking
# at — name, type and region together — since the region is not visible as an
# input variable.
output "cell_id" {
  value = local.cell_id
}

output "region" {
  value = data.aws_region.current.region
}

output "bedrock_models_available" {
  value = module.bedrock_enablement.models_available_count
}

output "platform_log_group" {
  value = module.cell_observability.platform_log_group
}

output "cur_exports_bucket" {
  value = module.cell_cost.cur_exports_bucket
}

output "runtime_role_arn" {
  value = module.runtime_iam.runtime_role_arn
}

output "runtime_log_group" {
  value = module.runtime_iam.runtime_log_group
}

output "application_log_group" {
  value = module.runtime_iam.application_log_group
}

output "bedrock_invocations_log_group" {
  value = module.runtime_iam.bedrock_invocations_log_group
}

output "policy_engine_arn" {
  value = module.policy_engine.policy_engine_arn
}

output "policy_engine_id" {
  value = module.policy_engine.policy_engine_id
}

output "policy_engine_kms_key_arn" {
  value = module.policy_engine.kms_key_arn
}

output "gateway_id" {
  value = module.gateway.gateway_id
}

output "gateway_arn" {
  value = module.gateway.gateway_arn
}

output "gateway_role_arn" {
  value = module.gateway.gateway_role_arn
}

output "default_guardrail_id" {
  value = module.guardrail.guardrail_id
}

output "default_guardrail_version" {
  value = module.guardrail.guardrail_version
}
