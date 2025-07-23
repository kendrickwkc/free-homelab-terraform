# ── OCI Bastion (private cluster + MySQL access) ──────────
# The persistent bastion host is managed here. Port-forwarding *sessions* are
# short-lived (TTL) and created on demand (see docs/bastion.md), so they are
# not resources in this config.

resource "oci_bastion_bastion" "homelab" {
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_ocid
  target_subnet_id             = oci_core_subnet.public_subnet.id
  name                         = "homelab-bastion"
  client_cidr_block_allow_list = ["0.0.0.0/0"]
}
