terraform {
  # Partial backend configuration - cluster-specific path provided via backend config file
  # Backend config file: ../clusters/<cluster_name>/backend-infrastructure.hcl
  # State file location: ../clusters/<cluster_name>/infrastructure.tfstate
  # To use remote S3 backend, uncomment and configure the backend block below:
  #
  # backend "s3" {
  #   bucket         = "my-org-terraform-state"
  #   key            = "examples/egress-zero/clusters/<cluster_name>/infrastructure.tfstate"
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

provider "rhcs" {
  token = var.token
  url   = "https://api.openshift.com"
}
