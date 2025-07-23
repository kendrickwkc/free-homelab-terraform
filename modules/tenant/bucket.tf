data "oci_objectstorage_namespace" "ns" {}

resource "oci_objectstorage_bucket" "buckets" {
  for_each       = toset(var.buckets)
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = each.key
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
}
