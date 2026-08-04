# ── Bedrock enablement check (sheet: "Enable AWS Bedrock in the Cell 1
#    account") — Cell Provisioning. There is no explicit "enable" resource for
#    Bedrock — access is granted at the account/model level. This data source
#    proves the AWS credentials driving this cell's workspace can already
#    reach the Bedrock control plane, which is the practical definition of
#    "enabled" for automation purposes. ──
data "aws_bedrock_foundation_models" "available" {}
