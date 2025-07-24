variable "region" {
  description = "OCI region"
  type        = string
}

variable "oci_namespace" {
  description = "Tenancy object storage namespace"
  type        = string
}

variable "tenancy_id" {
  description = "OCI tenancy (root compartment) OCID"
  type        = string
}

variable "zone" {
  description = "Cloudflare zone (domain) name"
  type        = string
}

variable "cf_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "cf_api_token" {
  description = "Cloudflare API token (zone-scoped to this tenant's zone)"
  type        = string
  sensitive   = true
}
