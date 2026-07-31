variable "aws_region" {
  description = "AWS region for the platform"
  type        = string
  default     = "us-east-1"
}

variable "project_prefix" {
  description = "Naming prefix for all platform resources"
  type        = string
  default     = "toyota-full"
}
