terraform {
  # Default: Local state storage (terraform.tfstate in this directory)
  # To use remote S3 backend, uncomment and configure the backend block below:
  #
  # backend "s3" {
  #   bucket         = "my-org-terraform-state"
  #   key            = "examples/public/configuration/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }

  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7"
    }
  }
}

# Read infrastructure outputs via remote state
data "terraform_remote_state" "infrastructure" {
  backend = "local"
  config = {
    path = "../infrastructure/terraform.tfstate"
  }
}

# Configure Kubernetes provider for OpenShift cluster
provider "kubernetes" {
  host     = data.terraform_remote_state.infrastructure.outputs.api_url
  username = var.admin_username
  password = var.admin_password
  insecure = var.skip_tls_verify
}

# RHCS provider for identity-admin module
provider "rhcs" {
  token = var.token
  url   = "https://api.openshift.com"
}
