terraform {
  # Partial backend configuration - cluster-specific path provided via backend config file
  # Backend config file: ../clusters/<cluster_name>/backend-configuration.hcl
  # State file location: ../clusters/<cluster_name>/configuration.tfstate
  # To use remote S3 backend, uncomment and configure the backend block below:
  #
  # backend "s3" {
  #   bucket         = "my-org-terraform-state"
  #   key            = "examples/egress-zero/clusters/<cluster_name>/configuration.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }

  # Use partial backend configuration - path provided via backend config file
  # Backend config file contains: path = "../clusters/<cluster_name>/configuration.tfstate"
  backend "local" {
    # path provided via backend config file during init
  }

  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0.0"
    }
    openshift = {
      source  = "registry.terraform.io/rh-mobb/openshift"
      version = "0.1.2"
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
# Infrastructure state is in clusters/<cluster_name>/infrastructure.tfstate
# Cluster name is determined from terraform.tfvars in clusters/<cluster_name>/
data "terraform_remote_state" "infrastructure" {
  backend = "local"
  config = {
    path = "../clusters/${var.cluster_name}/infrastructure.tfstate"
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

# # RHCS provider for identity-admin module
# provider "rhcs" {
#   token = var.token
#   url   = "https://api.openshift.com"
# }
