# Example tenant — copy this directory into your project repo as `infra/`.
#
# This repo is a template: after "Use this template", YOUR copy hosts the
# tenant module. Project repos consume it from your copy (replace
# <your-username>, pin a tag, bump the tag to pull module fixes from upstream).
# Local dev (inside this repo): use source = "../../modules/tenant"

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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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
  # Local dev / in-repo validation (shipped default):
  source = "../../modules/tenant"
  # Project repo (after copying, inside your template copy):
  # source = "github.com/<your-username>/oci-k8s-template//modules/tenant?ref=v1.1.0"

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
