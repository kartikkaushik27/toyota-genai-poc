data "aws_caller_identity" "current" {}

# ── Cost analysis export bucket — ONE PER CELL (sheet: "Set up an S3 bucket to
#    receive CUR2.0 data exports for cost analysis") — Cell Provisioning.
#
#    Previously a single global bucket created once in infra/platform-a. Moved
#    here and parameterized by cell_name so every cell gets its own CUR export
#    bucket instead of every cell's cost data landing in one shared platform
#    bucket. Adding a new cell (cells/cell2/...) automatically gets its own
#    bucket for free by instantiating this module again. ──
resource "aws_s3_bucket" "cur_exports" {
  bucket = "${var.project_prefix}-${var.cell_name}-cur-exports-${data.aws_caller_identity.current.account_id}"
  tags   = { Project = "toyota-genai-full", Cell = var.cell_name, Purpose = "cost-analysis" }
}

resource "aws_s3_bucket_public_access_block" "cur_exports" {
  bucket                  = aws_s3_bucket.cur_exports.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
