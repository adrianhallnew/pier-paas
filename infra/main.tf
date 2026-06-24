terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

provider "oci" {
  config_file_profile = "DEFAULT"
  region              = var.region
}

# ── Data sources ─────────────────────────────────────────────────────────────

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu_24" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ── Networking ────────────────────────────────────────────────────────────────

resource "oci_core_vcn" "pier" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "pier-vcn"
  dns_label      = "pier"
}

resource "oci_core_internet_gateway" "pier" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.pier.id
  display_name   = "pier-igw"
  enabled        = true
}

resource "oci_core_route_table" "pier" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.pier.id
  display_name   = "pier-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.pier.id
  }
}

resource "oci_core_security_list" "pier" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.pier.id
  display_name   = "pier-sl"

  ingress_security_rules {
    protocol  = "6"
    source    = var.operator_cidr
    stateless = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 443
      max = 443
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }
}

resource "oci_core_subnet" "pier" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.pier.id
  cidr_block                 = "10.0.0.0/24"
  display_name               = "pier-subnet"
  dns_label                  = "main"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.pier.id
  security_list_ids          = [oci_core_security_list.pier.id]
}

# ── Compute ───────────────────────────────────────────────────────────────────

resource "oci_core_instance" "pier" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "pier-vm"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu_24.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.pier.id
    display_name     = "pier-vnic"
    assign_public_ip = false
    hostname_label   = "pier"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_pubkey
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      duckdns_token = var.duckdns_token
      duckdns_root  = var.duckdns_root
      ssh_pubkey    = var.ssh_pubkey
      repo_url      = var.repo_url
    }))
  }
}

# ── Reserved public IP ────────────────────────────────────────────────────────

data "oci_core_vnic_attachments" "pier" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  instance_id         = oci_core_instance.pier.id
}

data "oci_core_vnic" "pier" {
  vnic_id = data.oci_core_vnic_attachments.pier.vnic_attachments[0].vnic_id
}

data "oci_core_private_ips" "pier" {
  vnic_id = data.oci_core_vnic.pier.id
}

resource "oci_core_public_ip" "pier" {
  compartment_id = var.compartment_ocid
  lifetime       = "RESERVED"
  display_name   = "pier-ip"
  private_ip_id  = data.oci_core_private_ips.pier.private_ips[0].id
}

# ── Block volume (200 GB for /var/lib/docker) ─────────────────────────────────

resource "oci_core_volume" "pier_docker" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "pier-docker-vol"
  size_in_gbs         = 200
}

resource "oci_core_volume_attachment" "pier_docker" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.pier.id
  volume_id       = oci_core_volume.pier_docker.id
  display_name    = "pier-docker-attach"
  is_read_only    = false
  is_shareable    = false
}
