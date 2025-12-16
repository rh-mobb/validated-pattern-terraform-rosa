terraform {
  # Default: Local state storage (terraform.tfstate in this directory)
  # To use remote S3 backend, uncomment and configure the backend block below:
  #
  # backend "s3" {
  #   bucket         = "my-org-terraform-state"
  #   key            = "examples/private/infrastructure/terraform.tfstate"
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
  token = var.token
  url   = "https://api.openshift.com"
}
