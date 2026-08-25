# Example tenant — copy this directory into your project repo as `infra/`.
#
# Local dev (inside this repo): use source = "../../modules/tenant"
# Project repo:                  use the git source below (replace username, pin a tag)

terraform {
  required_version = ">= 1.5"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
  # Tenant state lives in the shared terraform-state bucket under its own key:
  #   terraform init -backend-config=backend.tfbackend
  backend "oci" {}
}

provider "oci" {
  region = var.region
}

provider "cloudflare" {
  api_token = var.cf_api_token
}

data "terraform_remote_state" "platform" {
  backend = "oci"
  config = {
    bucket    = "terraform-state"
    namespace = var.oci_namespace
    region    = var.region
    key       = "platform/terraform.tfstate"
  }
}

module "tenant" {
  source = "github.com/your-github-username/free-homelab-terraform//modules/tenant?ref=main"

  name           = "example"
  zone           = var.zone
  cf_account_id  = var.cf_account_id
  tenancy_id     = var.tenancy_id
  compartment_id = data.terraform_remote_state.platform.outputs.compartment_id
  region         = var.region

  buckets = ["example-assets", "example-backups"]

  worker_enabled = true
  assets_bucket  = "example-assets"
}

output "tunnel_token" {
  value     = module.tenant.tunnel_token
  sensitive = true
}

output "s3_access_key" {
  value     = module.tenant.s3_access_key
  sensitive = true
}

output "s3_secret_key" {
  value     = module.tenant.s3_secret_key
  sensitive = true
}
