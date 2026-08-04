variable "project_prefix" {
  description = "Naming prefix shared across all resources"
  type        = string
}

variable "cell_name" {
  description = "Name of this cell (e.g. cell1) — used to namespace resources per cell"
  type        = string
}
