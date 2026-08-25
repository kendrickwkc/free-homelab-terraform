# ── Cloudflare: per-tenant tunnel + optional assets Worker ──

data "cloudflare_zone" "zone" {
  name = var.zone
}

resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "app" {
  account_id = var.cf_account_id
  name       = "${var.name}-app"
  secret     = random_id.tunnel_secret.b64_std
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "app" {
  account_id = var.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.app.id

  config {
    ingress_rule {
      hostname = local.fqdn
      service  = local.app_service
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}

resource "cloudflare_record" "app" {
  zone_id = data.cloudflare_zone.zone.zone_id
  name    = var.hostname
  type    = "CNAME"
  content = cloudflare_zero_trust_tunnel_cloudflared.app.cname
  proxied = true
  ttl     = 1
}

# ── Assets Worker (optional) ──────────────────────────────
# Serves a private bucket over Cloudflare using the OCI S3-compatible API.

resource "cloudflare_workers_script" "assets" {
  count              = var.worker_enabled ? 1 : 0
  account_id         = var.cf_account_id
  name               = "${var.name}-assets"
  content            = file(coalesce(var.worker_script_path, "${path.module}/files/worker.js"))
  compatibility_date = "2023-01-01"

  plain_text_binding {
    name = "OCI_NAMESPACE"
    text = data.oci_objectstorage_namespace.ns.namespace
  }
  plain_text_binding {
    name = "OCI_REGION"
    text = var.region
  }
  plain_text_binding {
    name = "OCI_BUCKET"
    text = var.assets_bucket
  }
  secret_text_binding {
    name = "OCI_S3_ACCESS_KEY"
    text = oci_identity_customer_secret_key.tenant.id
  }
  secret_text_binding {
    name = "OCI_S3_SECRET_KEY"
    text = oci_identity_customer_secret_key.tenant.key
  }
}

resource "cloudflare_workers_domain" "assets" {
  count      = var.worker_enabled ? 1 : 0
  account_id = var.cf_account_id
  zone_id    = data.cloudflare_zone.zone.zone_id
  hostname   = local.assets_fqdn
  service    = cloudflare_workers_script.assets[0].name
}
