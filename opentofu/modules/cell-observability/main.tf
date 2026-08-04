# ── CloudWatch: admin + Model Gateway API debugging, per cell (sheet: "Set up
#    cloudwatch logs for both admin and model gateway service for backend API
#    debugging") — Cell Provisioning.
#
#    Relocated here from infra/platform-a: this log group captures activity
#    happening INSIDE this specific cell (the Model Gateway calling into this
#    cell's Bedrock endpoint, this cell's admin-facing API surface), so it
#    belongs to Cell Provisioning, not to the shared platform account. ──
resource "aws_cloudwatch_log_group" "platform" {
  name              = "/${var.project_prefix}/${var.cell_name}/platform"
  retention_in_days = 14
  tags              = { Project = "toyota-genai-full", Cell = var.cell_name }
}
