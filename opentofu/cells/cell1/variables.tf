variable "aws_region" {
  description = "AWS region this cell is deployed in"
  type        = string
  default     = "us-east-1"
}

variable "project_prefix" {
  description = "Naming prefix for all resources"
  type        = string
  default     = "toyota-full"
}

variable "cell_name" {
  description = "Name of this cell — MUST match the directory name (cells/cell1 -> \"cell1\")"
  type        = string
  default     = "cell1"
}
