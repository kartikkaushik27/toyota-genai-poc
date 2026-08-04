# Values are NOT defaulted here on purpose. Cell identity is supplied at run
# time by the provision-cell pipeline (pipeline variables -> IaCM workspace
# OpenTofu variables), so the cell config stays a pure "declare inputs, call
# modules" shell. Harness variable precedence is:
#   workspace variables > variable sets > HCL defaults
# — leaving defaults out means a missing pipeline input fails loudly instead
# of silently provisioning a cell named "cell1".
#
# project_prefix is deliberately NOT a variable here: there is one prefix for
# the entire platform, defined once in opentofu/modules/naming.
#
# For a local run, pass the inputs explicitly:
#   tofu plan -var-file=env/us-east-1/dev.tfvars

variable "aws_region" {
  description = "AWS region this cell is deployed in"
  type        = string
}

variable "cell_name" {
  description = "Name of this cell (e.g. cell1) — namespaces every resource in the cell"
  type        = string
}
