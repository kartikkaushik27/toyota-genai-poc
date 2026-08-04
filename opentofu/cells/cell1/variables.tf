# cell_name is the only input. Everything else is derived:
#   - region comes from the workspace's AWS_DEFAULT_REGION (see providers.tf),
#     so the same directory serves every region we deploy this cell into
#   - project_prefix is platform-wide and defined in opentofu/modules/naming
#
# No default on purpose: Harness resolves workspace variables ahead of HCL
# defaults, so a missing pipeline input should fail loudly rather than
# quietly provisioning something called "cell1".

variable "cell_name" {
  description = "Name of this cell (e.g. cell1). Combined with the region to namespace every resource in this cell instance."
  type        = string
}
