# NOTE: the block is still named `terraform { }` even though this repo now
# targets OpenTofu — OpenTofu kept this block label for drop-in compatibility
# with existing Terraform configuration syntax. This is intentional, not a
# leftover from the Terraform version of this file.
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

  # New state key — this cell's resource addresses (module.policy_engine.*,
  # module.gateway.*, etc.) do not match the old flat infra/platform-b-cell
  # addresses, so this is treated as a fresh workspace rather than an
  # in-place migration of the old state. Expect the first plan against this
  # config to show full destroy+recreate of every AgentCore resource
  # (Policy Engine, Gateway, Guardrail, Runtime role, log groups) even where
  # the desired end-state didn't actually change — that's a one-time cost of
  # introducing the module boundaries, not a bug. The Policy Engine and
  # Gateway would have needed recreation anyway (KMS encryption is ForceNew;
  # switching CUSTOM_JWT -> AWS_IAM is ForceNew).
  backend "s3" {
    bucket = "toyota-poc-tfstate-915632791698"
    key    = "cells/cell1/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}
