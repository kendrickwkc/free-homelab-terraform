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
  default     = "v1.36.1"
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

# ── Topology (defaults keep the Always Free layout) ───────

variable "cluster_name" {
  description = "OKE cluster display name"
  type        = string
  default     = "homelab-cluster"
}

variable "vcn_cidr" {
  description = "VCN CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR (bastion, service LBs)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_subnet_cidr" {
  description = "Private subnet CIDR (MySQL, OKE API private endpoint)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "worker_subnet_cidr" {
  description = "Worker subnet CIDR (OKE nodes)"
  type        = string
  default     = "10.0.2.0/24"
}

# ── Node pools (consume the A1 free allowance: 4 OCPU / 24 GB) ──

variable "node_general_ocpus" {
  description = "General pool: OCPUs per node (stateful, storage=true)"
  type        = number
  default     = 2
}

variable "node_general_memory" {
  description = "General pool: memory GB per node"
  type        = number
  default     = 12
}

variable "node_general_size" {
  description = "General pool: node count"
  type        = number
  default     = 1
}

variable "node_small_ocpus" {
  description = "Small pool: OCPUs per node (stateless)"
  type        = number
  default     = 1
}

variable "node_small_memory" {
  description = "Small pool: memory GB per node"
  type        = number
  default     = 6
}

variable "node_small_size" {
  description = "Small pool: node count"
  type        = number
  default     = 2
}

variable "boot_volume_size_gb" {
  description = "Boot volume size per node (3 nodes consume 150 GB of the 200 GB Always Free block budget)"
  type        = number
  default     = 50
}

# ── MySQL ─────────────────────────────────────────────────

variable "mysql_admin_username" {
  description = "Shared MySQL HeatWave admin username"
  type        = string
  default     = "admin"
}

# ── Access hardening ──────────────────────────────────────

variable "bastion_client_cidrs" {
  description = "CIDR blocks allowed to reach the bastion service and its SSH port (set to your tailnet CIDR once Tailscale is running)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
