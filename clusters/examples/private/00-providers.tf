terraform {
  # Default: Local state storage (terraform.tfstate in this directory)
  # To use remote S3 backend, uncomment and configure the backend block below:
  #
  # backend "s3" {
  #   bucket         = "my-org-terraform-state"
  #   key            = "examples/private/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }

  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

provider "rhcs" {
  # Token can be provided via:
  # 1. Variable: var.token (set in terraform.tfvars or via TF_VAR_token environment variable)
  # 2. Environment variable: OCM_TOKEN or ROSA_TOKEN (if var.token is not set)
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/00-provider.tf
  # Get token from: https://console.redhat.com/openshift/token/rosa/show
  token = var.token
  url   = "https://api.openshift.com"
  # Optional: Custom token URL and client settings
  # token_url     = "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"
  # client_id     = "cloud-services"
  # client_secret = "" # Empty string uses default client secret
}
