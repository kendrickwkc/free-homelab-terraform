variable "region" {
  description = "OCI region (must be your tenancy home region for Always Free)"
  type        = string
}

variable "tenancy_ocid" {
  description = "OCI tenancy (root compartment) OCID"
  type        = string
  sensitive   = true
}

variable "compartment_ocid" {
  description = "OCI compartment OCID"
  type        = string
  sensitive   = true
}

variable "availability_domain" {
  description = "OCI availability domain name for the node pools (from the OCI console / oci iam availability-domain list)"
  type        = string
}

variable "kubernetes_version" {
  description = "OKE Kubernetes version (from oci ce cluster create-options)"
  type        = string
  default     = "v1.34.2"
}

variable "ssh_public_key" {
  description = "SSH public key for OKE node pools and bastion sessions"
  type        = string
}

variable "mysql_admin_password" {
  description = "Shared MySQL HeatWave admin password"
  type        = string
  sensitive   = true
}

variable "monthly_budget_usd" {
  description = "Monthly budget cap in USD"
  type        = number
  default     = 1
}

variable "budget_alert_email" {
  description = "Email to receive budget and alarm alerts"
  type        = string
}
