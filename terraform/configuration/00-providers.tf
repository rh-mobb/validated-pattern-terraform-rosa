terraform {
  # Backend configuration is provided via -backend-config flags or environment variables
  # For local development: terraform init -backend-config="path=../../clusters/<name>/configuration.tfstate"
  # For CI/CD with S3: terraform init -backend-config="bucket=..." -backend-config="key=..." etc.
  # Default to local backend, but can be overridden via -backend-config flags
  backend "local" {
    # path provided via -backend-config flag or environment variable
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

# Configure Kubernetes provider for OpenShift cluster
# Token is obtained via 'oc login' by the Makefile and passed as TF_VAR_k8s_token
# API URL comes from infrastructure outputs passed as input variable
provider "kubernetes" {
  host     = var.api_url
  token    = var.k8s_token
  insecure = var.skip_tls_verify
}

# Configure OpenShift Operator provider
# Uses the same credentials as Kubernetes provider
provider "openshift" {
  host     = var.api_url
  token    = var.k8s_token
  insecure = var.skip_tls_verify
}
