# =============================================================================
# provider.tf
# CISC 886 — Cloud Computing
# Configures the AWS Terraform provider and sets the deployment region.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"   # pin to major version 5 to avoid breaking changes
    }
  }
}

# The AWS provider reads credentials from environment variables:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN
# These are set automatically when you use AWS Academy / Learner Lab.
# Never hard-code credentials in Terraform files.
provider "aws" {
  region = var.aws_region
}
