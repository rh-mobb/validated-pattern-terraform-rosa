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
      version = "~> 3.0.0"
    }
    openshift = {
      source  = "registry.terraform.io/rh-mobb/openshift"
      version = "0.1.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    # rhcs = {
    #   source  = "terraform-redhat/rhcs"
    #   version = "~> 1.7"
    # }
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
# Token is obtained via 'oc login' by the Makefile and passed as TF_VAR_k8s_token
provider "kubernetes" {
  host     = data.terraform_remote_state.infrastructure.outputs.api_url
  token    = var.k8s_token
  insecure = var.skip_tls_verify
}

# Configure OpenShift Operator provider
# Uses the same credentials as Kubernetes provider
provider "openshift" {
  host     = data.terraform_remote_state.infrastructure.outputs.api_url
  token    = var.k8s_token
  insecure = var.skip_tls_verify
}
