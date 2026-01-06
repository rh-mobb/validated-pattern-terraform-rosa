terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    rhcs = {
      # Registry provider - not used by this module (we use rhcs_local alias)
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7"
    }
    rhcs-local = {
      # Local custom provider with audit_log_arn support - used for cluster resource
      source  = "terraform.local/local/rhcs"
      version = "1.7.2"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}
