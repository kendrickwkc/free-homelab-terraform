# ── Shared MySQL HeatWave (Always Free) ───────────────────
# One MySQL.Free DB system is allowed per tenancy; tenants share it and get
# their own databases/users (created manually via the bastion, see docs/onboarding.md).

data "oci_mysql_mysql_configurations" "default_config" {
  compartment_id = var.compartment_ocid
  type           = ["DEFAULT"]
  shape_name     = "MySQL.Free"
}

resource "oci_mysql_mysql_db_system" "db" {
  compartment_id      = var.compartment_ocid
  admin_username      = "admin"
  admin_password      = var.mysql_admin_password
  availability_domain = var.availability_domain
  display_name        = "homelab-mysql"
  shape_name          = "MySQL.Free"
  subnet_id           = oci_core_subnet.private_subnet.id
  configuration_id    = data.oci_mysql_mysql_configurations.default_config.configurations[0].id

  data_storage_size_in_gb = 50
  hostname_label          = "homelab"
  is_highly_available     = false

  deletion_policy {
    is_delete_protected = true
  }
}
