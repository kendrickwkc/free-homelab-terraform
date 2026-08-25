data "oci_objectstorage_namespace" "ns" {}

data "oci_identity_region_subscriptions" "current" {
  tenancy_id = var.tenancy_ocid
}

locals {
  region_key = [for s in data.oci_identity_region_subscriptions.current.region_subscriptions
  : lower(s.region_key) if s.region_name == var.region][0]
}

output "compartment_id" {
  description = "Compartment OCID (tenants read this via remote state)"
  value       = var.compartment_ocid
}

output "tenancy_ocid" {
  description = "Tenancy (root compartment) OCID (tenants read this via remote state)"
  value       = var.tenancy_ocid
}

output "region" {
  description = "Region name"
  value       = var.region
}

output "region_key" {
  description = "Short region key (used to build OCIR image URLs: <region_key>.ocir.io/<namespace>/<repo>)"
  value       = local.region_key
}

output "object_storage_namespace" {
  description = "Tenancy object storage namespace"
  value       = data.oci_objectstorage_namespace.ns.namespace
}

output "cluster_id" {
  description = "OKE cluster OCID"
  value       = oci_containerengine_cluster.oke.id
}

output "cluster_private_endpoint" {
  description = "OKE API private endpoint (ip:port)"
  value       = oci_containerengine_cluster.oke.endpoints[0].private_endpoint
}

output "mysql_host" {
  description = "Shared MySQL hostname (private VCN DNS)"
  value       = "${oci_mysql_mysql_db_system.db.hostname_label}.private.${oci_core_vcn.vcn.dns_label}.oraclevcn.com"
}

output "bastion_id" {
  description = "OCID of the OCI Bastion"
  value       = oci_bastion_bastion.homelab.id
}

output "kubeconfig_command" {
  description = "Command to generate a kubeconfig for the private endpoint"
  value       = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.oke.id} --file kubeconfig --region ${var.region} --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT"
}
