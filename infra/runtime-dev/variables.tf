variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_prefix" {
  type    = string
  default = "toyota-full"
}

variable "image_tag" {
  description = "ECR image tag to deploy (pushed by Agent CI Build)"
  type        = string
  default     = "latest"
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
