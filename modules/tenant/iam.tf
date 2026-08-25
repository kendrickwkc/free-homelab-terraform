# ── Per-tenant OCI identity ───────────────────────────────
# One user + group + customer secret key. The key is used both by the
# Cloudflare assets Worker (S3 SigV4 read) and by any in-cluster job (e.g. a
# backup CronJob) that talks to Object Storage. It is scoped, via policy, to
# only the tenant's own buckets.

resource "oci_identity_user" "tenant" {
  compartment_id = var.tenancy_id
  name           = var.name
  description    = "${var.name} tenant: bucket + Cloudflare Worker access"
  email          = "${var.name}@${var.zone}"
}

resource "oci_identity_group" "tenant" {
  compartment_id = var.tenancy_id
  name           = var.name
  description    = "${var.name} tenant group"
}

resource "oci_identity_user_group_membership" "tenant" {
  compartment_id = var.tenancy_id
  user_id        = oci_identity_user.tenant.id
  group_id       = oci_identity_group.tenant.id
}

resource "oci_identity_customer_secret_key" "tenant" {
  user_id      = oci_identity_user.tenant.id
  display_name = "${var.name}-s3"
}

resource "oci_identity_policy" "tenant" {
  compartment_id = var.tenancy_id
  name           = var.name
  description    = "Scoped object access for the ${var.name} tenant"
  statements = [
    for b in var.buckets :
    "Allow group ${var.name} to manage objects in tenancy where target.bucket.name = '${b}'"
  ]
}
