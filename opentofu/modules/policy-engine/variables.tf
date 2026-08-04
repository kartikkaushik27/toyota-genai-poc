variable "project_prefix" {
  description = "Naming prefix shared across all resources"
  type        = string
}

variable "cell_name" {
  description = "Name of this cell (e.g. cell1) — used to namespace resources per cell"
  type        = string
}

variable "runtime_role_arn" {
  description = "ARN of this cell's Runtime execution role (from the runtime-iam module) — the baseline Cedar policy permits only this principal to call tools through the Gateway."
  type        = string
}
