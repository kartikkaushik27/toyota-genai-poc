#!/usr/bin/env bash
# Tenant Onboarding script — mirrors Pipeline 4 "Tenant Registration" from the
# Toyota GenAI use case. Real design calls for a "script/orchestration
# pipeline" here rather than full Terraform, since resources are created
# on-the-fly per tenant and outside the main IaC state.
#
# Usage: ./onboard.sh <tenant_name>
set -euo pipefail

TENANT_NAME="${1:?Usage: onboard.sh <tenant_name>}"
PROJECT_PREFIX="toyota-poc"
AWS_REGION="${AWS_REGION:-us-east-1}"
TABLE_NAME="${PROJECT_PREFIX}-tenant-registry"

echo "== Onboarding tenant: ${TENANT_NAME} =="

# 1. Per-tenant CloudWatch log group (mirrors "Configure CloudWatch log group
#    in Cell 1 for each new tenant")
LOG_GROUP="/${PROJECT_PREFIX}/tenant/${TENANT_NAME}"
echo "-- Creating CloudWatch log group: ${LOG_GROUP}"
aws logs create-log-group --log-group-name "${LOG_GROUP}" --region "${AWS_REGION}" 2>/dev/null || echo "   (already exists)"
aws logs put-retention-policy --log-group-name "${LOG_GROUP}" --retention-in-days 14 --region "${AWS_REGION}"

# 2. Per-tenant Bedrock Guardrail (mirrors "Create a Bedrock guardrail in
#    Cell 1 for each new tenant")
echo "-- Creating Bedrock Guardrail for ${TENANT_NAME}"
GUARDRAIL_JSON=$(aws bedrock create-guardrail \
  --name "${PROJECT_PREFIX}-${TENANT_NAME}-guardrail" \
  --description "Auto-provisioned guardrail for tenant ${TENANT_NAME}" \
  --blocked-input-messaging "This request cannot be processed due to content policy." \
  --blocked-outputs-messaging "This response cannot be shown due to content policy." \
  --content-policy-config '{
    "filtersConfig": [
      {"type": "SEXUAL", "inputStrength": "HIGH", "outputStrength": "HIGH"},
      {"type": "VIOLENCE", "inputStrength": "HIGH", "outputStrength": "HIGH"},
      {"type": "HATE", "inputStrength": "HIGH", "outputStrength": "HIGH"},
      {"type": "INSULTS", "inputStrength": "MEDIUM", "outputStrength": "MEDIUM"},
      {"type": "MISCONDUCT", "inputStrength": "HIGH", "outputStrength": "HIGH"}
    ]
  }' \
  --region "${AWS_REGION}" 2>&1) || {
    echo "   Guardrail may already exist, looking it up..."
    GUARDRAIL_JSON=$(aws bedrock list-guardrails --region "${AWS_REGION}" \
      --query "guardrails[?name=='${PROJECT_PREFIX}-${TENANT_NAME}-guardrail']" --output json)
  }
echo "${GUARDRAIL_JSON}"
GUARDRAIL_ID=$(echo "${GUARDRAIL_JSON}" | python3 -c "import json,sys; d=json.load(sys.stdin); d=d[0] if isinstance(d,list) else d; print(d.get('guardrailId',''))" 2>/dev/null || echo "unknown")

# 3. Per-tenant cross-account IAM role (mirrors "Create a cross-account IAM
#    role and policy in Cell 1 for each new tenant")
ROLE_NAME="${PROJECT_PREFIX}-${TENANT_NAME}-role"
echo "-- Creating tenant IAM role: ${ROLE_NAME}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::${ACCOUNT_ID}:root" },
    "Action": "sts:AssumeRole"
  }]
}
EOF
aws iam create-role --role-name "${ROLE_NAME}" --assume-role-policy-document file:///tmp/trust-policy.json --region "${AWS_REGION}" 2>/dev/null || echo "   (role already exists)"

# 4. Register the tenant as Active in the tenant registry (mirrors "Update
#    the tenant status to Active in DynamoDB after provisioning completes")
echo "-- Writing tenant record to DynamoDB: ${TABLE_NAME}"
aws dynamodb put-item \
  --table-name "${TABLE_NAME}" \
  --item "{
    \"tenant_id\": {\"S\": \"${TENANT_NAME}\"},
    \"status\": {\"S\": \"Active\"},
    \"guardrail_id\": {\"S\": \"${GUARDRAIL_ID}\"},
    \"iam_role\": {\"S\": \"arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}\"},
    \"log_group\": {\"S\": \"${LOG_GROUP}\"},
    \"onboarded_at\": {\"S\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}
  }" \
  --region "${AWS_REGION}"

echo "== Tenant ${TENANT_NAME} onboarding complete. Status: Active =="
