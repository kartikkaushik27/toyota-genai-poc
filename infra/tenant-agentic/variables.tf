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

# ── Which cell instance this module attaches to. A cell instance is
#    (cell_name, cell_type, region); the region is implied by the provider, so
#    only the first two need naming here. These are variables rather than a
#    hardcoded "cell1" so a second cell or a prod cell needs no code change.
#
#    Note: the POC provisions a dev cell in each region, which is why
#    cell_type defaults to dev even for the prod Runtime. Point this at
#    cell_type = "prod" once a prod cell has been provisioned in the region.
variable "cell_name" {
  type    = string
  default = "cell1"
}

variable "cell_type" {
  type    = string
  default = "dev"
}
