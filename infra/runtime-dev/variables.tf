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
