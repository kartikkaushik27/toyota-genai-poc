variable "project_prefix" {
  description = "Naming prefix shared across all resources"
  type        = string
}

variable "cell_name" {
  description = "Name of this cell (e.g. cell1) — used to namespace resources per cell"
  type        = string
}

variable "policy_engine_arn" {
  description = "ARN of this cell's Policy Engine (from the policy-engine module) — associated with the Gateway to enforce Cedar policies on every tool call."
  type        = string
}
