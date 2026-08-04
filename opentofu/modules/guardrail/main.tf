# ── Cell-level default Guardrail, used to populate BEDROCK_GUARDRAIL_ID/
#    VERSION env vars on the Runtime. Per-tenant guardrails are created in
#    infra/tenant-registration and override this at the tenant level. ──
resource "aws_bedrock_guardrail" "default" {
  name                      = "${var.project_prefix}-${var.cell_name}-default-guardrail"
  blocked_input_messaging   = "This request cannot be processed due to content policy."
  blocked_outputs_messaging = "This response cannot be shown due to content policy."

  content_policy_config {
    filters_config {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
  }

  tags = { Project = "toyota-genai-full", Cell = var.cell_name }
}
