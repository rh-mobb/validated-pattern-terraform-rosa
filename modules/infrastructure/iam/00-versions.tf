terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    rhcs = {
      # Registry provider for IAM resources
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7"
    }
  }
}
