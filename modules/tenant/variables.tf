variable "name" {
  description = "Tenant name (lowercase, used as resource/prefix/k8s service name)"
  type        = string
}

variable "zone" {
  description = "Cloudflare zone (domain) name, e.g. example.com"
  type        = string
}

variable "hostname" {
  description = "Hostname within the zone for the app (use \"@\" for apex, or a subdomain label)"
  type        = string
  default     = "@"
}

variable "app_service" {
  description = "Upstream service the Cloudflare tunnel routes to (k8s service URL)"
  type        = string
  default     = null
}

variable "cf_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "tenancy_id" {
  description = "OCI tenancy (root compartment) OCID — identity resources must live here"
  type        = string
}

variable "compartment_id" {
  description = "OCI compartment OCID (buckets and policy live here)"
  type        = string
}

variable "region" {
  description = "OCI region (used by the assets Worker binding)"
  type        = string
}

variable "buckets" {
  description = "Object Storage buckets to create and grant the tenant identity access to"
  type        = list(string)
}

variable "worker_enabled" {
  description = "Create a Cloudflare Worker that serves a bucket over the OCI S3-compat API"
  type        = bool
  default     = false
}

variable "assets_bucket" {
  description = "Bucket served by the assets Worker (required when worker_enabled)"
  type        = string
  default     = null

  validation {
    condition     = !var.worker_enabled || var.assets_bucket != null
    error_message = "assets_bucket is required when worker_enabled is true"
  }
}

variable "assets_hostname" {
  description = "Hostname for the assets Worker (defaults to assets.<zone>)"
  type        = string
  default     = null
}

variable "worker_script_path" {
  description = "Path to a custom Worker script (defaults to the module's generic worker.js)"
  type        = string
  default     = null
}

locals {
  fqdn        = var.hostname == "@" ? var.zone : "${var.hostname}.${var.zone}"
  app_service = var.app_service != null ? var.app_service : "http://${var.name}:8080"
  assets_fqdn = var.assets_hostname != null ? var.assets_hostname : "assets.${var.zone}"
}
