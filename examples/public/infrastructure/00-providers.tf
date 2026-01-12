terraform {
  # Partial backend configuration - cluster-specific path provided via backend config file
  # Backend config file: ../clusters/<cluster_name>/backend-infrastructure.hcl
  # State file location: ../clusters/<cluster_name>/infrastructure.tfstate
  # To use remote S3 backend, uncomment and configure the backend block below:
  #
  # backend "s3" {
  #   bucket         = "my-org-terraform-state"
  #   key            = "examples/public/clusters/<cluster_name>/infrastructure.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }

  # Use partial backend configuration - path provided via backend config file
  # Backend config file contains: path = "../clusters/<cluster_name>/infrastructure.tfstate"
  backend "local" {
    # path provided via backend config file during init
  }

  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    rhcs = {
      # Official registry provider
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Local value for tags (use override if set, otherwise use tags variable)
locals {
  tags = var.tags_override != null ? var.tags_override : var.tags
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# Registry provider for most resources (IAM, OIDC, nested modules, etc.)
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
