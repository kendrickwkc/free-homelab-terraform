# ── OKE Cluster (private API endpoint) ────────────────────

resource "oci_containerengine_cluster" "oke" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = var.cluster_name
  vcn_id             = oci_core_vcn.vcn.id

  endpoint_config {
    is_public_ip_enabled = false
    subnet_id            = oci_core_subnet.private_subnet.id
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.public_subnet.id]
  }
}

data "oci_containerengine_node_pool_option" "options" {
  node_pool_option_id   = "all"
  compartment_id        = var.compartment_ocid
  node_pool_k8s_version = oci_containerengine_cluster.oke.kubernetes_version
}

locals {
  oke_image_ocid = [
    for source in data.oci_containerengine_node_pool_option.options.sources : source.image_id
    if length(regexall("Oracle-Linux-8.*aarch64", source.source_name)) > 0
  ][0]
}

# ── Node pools ────────────────────────────────────────────
# Defaults consume the A1 free allowance exactly: 4 OCPU / 24 GB total
# (memory is capped at 6 GB/OCPU). Sizes are variables — shrinking them
# frees headroom; growing them bills you.
#   general: 1x 2 OCPU / 12 GB, FD-1, labelled storage=true (stateful workloads)
#   small:   2x 1 OCPU / 6 GB,  FD-2 + FD-3 (stateless workloads)

resource "oci_containerengine_node_pool" "general" {
  cluster_id         = oci_containerengine_cluster.oke.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = "general"
  node_shape         = "VM.Standard.A1.Flex"

  node_shape_config {
    ocpus         = var.node_general_ocpus
    memory_in_gbs = var.node_general_memory
  }

  node_config_details {
    placement_configs {
      availability_domain = var.availability_domain
      fault_domains       = ["FAULT-DOMAIN-1"]
      subnet_id           = oci_core_subnet.worker_subnet.id
    }
    size = var.node_general_size
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = local.oke_image_ocid
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  initial_node_labels {
    key   = "name"
    value = "general"
  }

  initial_node_labels {
    key   = "storage"
    value = "true"
  }

  ssh_public_key = var.ssh_public_key
}

resource "oci_containerengine_node_pool" "small" {
  cluster_id         = oci_containerengine_cluster.oke.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = "small"
  node_shape         = "VM.Standard.A1.Flex"

  node_shape_config {
    ocpus         = var.node_small_ocpus
    memory_in_gbs = var.node_small_memory
  }

  node_config_details {
    placement_configs {
      availability_domain = var.availability_domain
      fault_domains       = ["FAULT-DOMAIN-2", "FAULT-DOMAIN-3"]
      subnet_id           = oci_core_subnet.worker_subnet.id
    }
    size = var.node_small_size
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = local.oke_image_ocid
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  initial_node_labels {
    key   = "name"
    value = "small"
  }

  ssh_public_key = var.ssh_public_key
}
