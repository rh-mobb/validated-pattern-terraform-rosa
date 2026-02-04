terraform {
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
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
    shell = {
      source  = "scottwinkler/shell"
      version = ">= 1.7.10"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}
