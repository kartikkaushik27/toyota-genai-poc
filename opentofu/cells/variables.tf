# The two inputs that identify which cell instance this run is provisioning.
# Region is deliberately absent — it arrives as AWS_DEFAULT_REGION from the
# workspace (see providers.tf), which is what lets one directory serve every
# region.
#
# Neither has a default: Harness resolves workspace variables ahead of HCL
# defaults, so a missing pipeline input should fail loudly rather than
# quietly provisioning something called "cell1 dev".

variable "cell_name" {
  description = "Name of the cell (e.g. cell1). Identifies the cell independently of which environment it serves."
  type        = string
}

variable "cell_type" {
  description = "Environment this cell instance serves: dev, test, stage or prod. A cell exists once per (name, type, region), and each combination is a separate workspace with its own state."
  type        = string

  validation {
    condition     = contains(["dev", "test", "stage", "prod"], var.cell_type)
    error_message = "cell_type must be one of: dev, test, stage, prod."
  }
}
