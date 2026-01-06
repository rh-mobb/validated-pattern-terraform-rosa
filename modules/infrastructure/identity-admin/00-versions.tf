terraform {
  required_version = ">= 1.5.0"

  required_providers {
    rhcs = {
      # Registry provider for identity admin resources
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7"
    }
  }
}
