# ── Network ────────────────────────────────────────────────
# Layout:
#   public  subnet (10.0.0.0/24): OCI Bastion only
#   private subnet (10.0.1.0/24): MySQL DB, OKE API private endpoint
#   worker  subnet (10.0.2.0/24): OKE worker nodes (egress via NAT/SGW)

resource "oci_core_vcn" "vcn" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "homelab-vcn"
  dns_label      = "homelab"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "homelab-igw"
}

resource "oci_core_nat_gateway" "nat" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "homelab-nat"
}

resource "oci_core_service_gateway" "sgw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "homelab-sgw"
  services {
    service_id = data.oci_core_services.all_services.services[0].id
  }
}

data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# ── Route tables ──────────────────────────────────────────

resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "public-rt"
  route_rules {
    network_entity_id = oci_core_internet_gateway.igw.id
    destination       = "0.0.0.0/0"
  }
}

resource "oci_core_route_table" "private_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "private-rt"
  route_rules {
    network_entity_id = oci_core_nat_gateway.nat.id
    destination       = "0.0.0.0/0"
  }
  route_rules {
    network_entity_id = oci_core_service_gateway.sgw.id
    destination_type  = "SERVICE_CIDR_BLOCK"
    destination       = data.oci_core_services.all_services.services[0].cidr_block
  }
}

# ── Security lists ────────────────────────────────────────

resource "oci_core_security_list" "public_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "public-sl"

  # SSH to the bastion (session auth handled by the Bastion service)
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_security_list" "private_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "private-sl"

  # MySQL (VCN internal)
  ingress_security_rules {
    protocol = "6"
    source   = "10.0.0.0/16"
    tcp_options {
      min = 3306
      max = 3306
    }
  }
  # Bastion -> OKE API private endpoint (port-forward session target)
  ingress_security_rules {
    protocol = "6"
    source   = "10.0.0.0/24"
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  # Worker nodes to/from API endpoint
  ingress_security_rules {
    protocol = "6"
    source   = "10.0.2.0/24"
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  # SSH from bastion to worker nodes (optional ops access)
  ingress_security_rules {
    protocol = "6"
    source   = "10.0.0.0/24"
    tcp_options {
      min = 22
      max = 22
    }
  }
  # Worker-to-worker and worker -> API endpoint/MySQL (flannel + kubelet)
  ingress_security_rules {
    protocol = "all"
    source   = "10.0.2.0/24"
  }
  # API endpoint -> worker nodes (kubelet 10250, etc.)
  ingress_security_rules {
    protocol = "all"
    source   = "10.0.1.0/24"
  }
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# ── Subnets ───────────────────────────────────────────────

resource "oci_core_subnet" "public_subnet" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.vcn.id
  cidr_block        = "10.0.0.0/24"
  route_table_id    = oci_core_route_table.public_rt.id
  security_list_ids = [oci_core_security_list.public_sl.id]
  display_name      = "public-subnet"
  dns_label         = "public"
}

resource "oci_core_subnet" "private_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.vcn.id
  cidr_block                 = "10.0.1.0/24"
  route_table_id             = oci_core_route_table.private_rt.id
  security_list_ids          = [oci_core_security_list.private_sl.id]
  display_name               = "private-subnet"
  dns_label                  = "private"
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "worker_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.vcn.id
  cidr_block                 = "10.0.2.0/24"
  route_table_id             = oci_core_route_table.private_rt.id
  security_list_ids          = [oci_core_security_list.private_sl.id]
  display_name               = "worker-subnet"
  dns_label                  = "worker"
  prohibit_public_ip_on_vnic = true
}
