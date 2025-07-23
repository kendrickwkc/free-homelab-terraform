terraform {
  required_version = ">= 1.5"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
  # Remote state is configured via a gitignored backend.tfbackend file:
  #   terraform init -backend-config=backend.tfbackend
  backend "oci" {}
}
