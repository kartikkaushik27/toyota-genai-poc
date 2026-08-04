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

variable "policy_engine_kms_key_arn" {
  description = "ARN of the CMK encrypting this cell's Policy Engine. The Gateway role needs KMS access to read a CMK-encrypted Policy Engine — without it, CreateGateway fails with \"Access denied while calling GetPolicyEngine\"."
  type        = string
}
