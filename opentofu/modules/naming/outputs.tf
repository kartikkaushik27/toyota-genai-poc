# Single source of truth for the platform-wide naming prefix.
#
# There is exactly ONE prefix for the whole platform — it is deliberately not
# a per-cell pipeline input, because every cell must agree on it or resource
# names stop being predictable across cells. Cells consume it with:
#
#   module "naming" { source = "../../modules/naming" }
#   locals { project_prefix = module.naming.project_prefix }
#
# Change it here and every cell picks it up on its next apply.
output "project_prefix" {
  description = "Naming prefix applied to every resource in every cell"
  value       = "toyota-full"
}
