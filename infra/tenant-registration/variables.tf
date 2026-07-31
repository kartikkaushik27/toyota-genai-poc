variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_prefix" {
  type    = string
  default = "toyota-full"
}

variable "tenant_name" {
  description = "Name of the tenant being registered (mirrors pipeline input from Tenant Registration)"
  type        = string
}
