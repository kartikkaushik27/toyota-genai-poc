variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_prefix" {
  type    = string
  default = "toyota-full"
}

variable "tenant_name" {
  description = "Name of the tenant (mirrors pipeline input from Agentic Tenant Provisioning)"
  type        = string
}

variable "gateway_id" {
  description = "Gateway ID output from the infra/platform-b-cell workspace (cross-workspace value, set as a workspace variable until IaCM native output-passing is used)"
  type        = string
}

variable "policy_engine_id" {
  description = "Policy Engine ID output from the infra/platform-b-cell workspace"
  type        = string
}
