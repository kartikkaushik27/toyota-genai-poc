variable "aws_region" {
  description = "AWS region for the cell"
  type        = string
  default     = "us-east-1"
}

variable "project_prefix" {
  description = "Naming prefix for all cell resources"
  type        = string
  default     = "toyota-full"
}
