output "app_hostname" {
  description = "Public app hostname (via the tenant's Cloudflare tunnel)"
  value       = local.fqdn
}

output "tunnel_token" {
  description = "Cloudflare tunnel token (seal into the tenant's cloudflared secret)"
  value       = cloudflare_zero_trust_tunnel_cloudflared.app.tunnel_token
  sensitive   = true
}

output "s3_access_key" {
  description = "Tenant customer secret key OCID (S3 access key)"
  value       = oci_identity_customer_secret_key.tenant.id
  sensitive   = true
}

output "s3_secret_key" {
  description = "Tenant customer secret key value (S3 secret key)"
  value       = oci_identity_customer_secret_key.tenant.key
  sensitive   = true
}

output "bucket_names" {
  description = "Buckets owned by this tenant"
  value       = var.buckets
}
