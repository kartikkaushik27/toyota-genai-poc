# NOTE: the block is still named `terraform { }` even though this repo targets
# OpenTofu — OpenTofu kept this block label for drop-in compatibility with
# existing Terraform configuration syntax.
#
# There is deliberately NO backend block. Harness IaCM stores and versions the
# state for each workspace itself (the run log shows it pulling state before a
# plan and uploading it after an apply), so declaring an S3 backend here would
# create a second, competing copy of the truth. One workspace = one state,
# held by Harness.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 6.19.0 is required: that's the release where `authorizer_configuration`
      # became optional on aws_bedrockagentcore_gateway for authorizer_type =
      # AWS_IAM. See opentofu/modules/gateway/main.tf.
      version = ">= 6.19.0, < 7.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}

# No region argument: the region comes from AWS_DEFAULT_REGION, which each
# per-region workspace sets. That is what keeps region out of the code and out
# of the pipeline inputs — the same cells/cell1 directory provisions us-east-1
# from one workspace and us-west-2 from another.
#
# For a local run: AWS_DEFAULT_REGION=us-west-2 tofu plan -var cell_name=cell1
provider "aws" {}
