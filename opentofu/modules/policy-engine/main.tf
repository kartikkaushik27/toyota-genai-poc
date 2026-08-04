data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── KMS customer-managed key for Policy Engine encryption (sheet: "Optionally
#    configure a KMS encryption key for the Policy Engine") — previously
#    skipped for POC simplicity; now built in.
#
#    The grant/usage statements are gated purely by `kms:ViaService` plus a
#    WILDCARD match on the Policy Engine's own encryption-context key, not an
#    exact Policy Engine ARN — the ARN doesn't exist yet at the time this key
#    policy is evaluated during `apply` (AWS assigns it), so an exact-ARN
#    condition would create an unresolvable chicken-and-egg dependency. This
#    mirrors AWS's own documented example for Policy Engine CMK policies. ──
resource "aws_kms_key" "policy_engine" {
  description             = "CMK for Bedrock AgentCore Policy Engine — ${var.cell_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowPolicyEngineCreateGrant"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = "kms:CreateGrant"
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService"          = "bedrock-agentcore.${data.aws_region.current.region}.amazonaws.com"
            "kms:GrantConstraintType" = "EncryptionContextSubset"
          }
          StringLike = {
            "kms:EncryptionContext:aws:bedrock-agentcore-policy:policy-engine-arn" = "arn:aws*:bedrock-agentcore:*:*:policy-engine/*"
          }
        }
      },
      {
        Sid       = "AllowPolicyEngineUsage"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "bedrock-agentcore.${data.aws_region.current.region}.amazonaws.com"
          }
          StringLike = {
            "kms:EncryptionContext:aws:bedrock-agentcore-policy:policy-engine-arn" = "arn:aws*:bedrock-agentcore:*:*:policy-engine/*"
          }
        }
      }
    ]
  })

  tags = { Project = "toyota-genai-full", Cell = var.cell_name }
}

resource "aws_kms_alias" "policy_engine" {
  name          = "alias/${var.project_prefix}-${var.cell_name}-policy-engine"
  target_key_id = aws_kms_key.policy_engine.key_id
}

# ── Policy Engine (sheet: "Deploy the Agentcore Policy Engine in Cell 1
#    before the Gateway") — Cell Provisioning. Now KMS-encrypted with the CMK
#    above instead of the AWS-managed default key. `encryption_key_arn` is
#    ForceNew on the AWS provider, so changing it later always means a
#    destroy+recreate of the Policy Engine, never an in-place update. ──
resource "aws_bedrockagentcore_policy_engine" "cell" {
  name               = "${replace(var.project_prefix, "-", "_")}_${replace(var.cell_name, "-", "_")}_policy_engine"
  description        = "Cedar policy engine for GenAI Platform ${var.cell_name} — evaluates every tool call made through the Gateway"
  encryption_key_arn = aws_kms_key.policy_engine.arn
}

# ── Baseline Cedar policy (sheet: "Create Cedar policies with permit and
#    forbid rules") — platform-wide default; per-tenant permit/forbid rules
#    are added in infra/tenant-agentic (kept separate so tenant policies don't
#    require re-applying this cell's workspace on every onboarding).
#
#    AWS's policy analyzer rejects any statement where principal, action, AND
#    resource are all unconstrained ("Overly Permissive") — so this scopes the
#    permit to the one principal that legitimately calls through the Gateway
#    on tenants' behalf: this cell's own Runtime execution role. ──
resource "aws_bedrockagentcore_policy" "default_permit" {
  name             = "default_permit_runtime_tools"
  policy_engine_id = aws_bedrockagentcore_policy_engine.cell.policy_engine_id
  description      = "Permit the ${var.cell_name} Runtime's execution role to call any tool through the Gateway"

  definition {
    cedar {
      statement = <<-EOT
        permit(
          principal == AgentCore::IamEntity::"${var.runtime_role_arn}",
          action,
          resource is AgentCore::Gateway
        );
      EOT
    }
  }
}
