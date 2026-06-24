variable "compartment_ocid" {
  type        = string
  description = "OCI compartment OCID (use root = tenancy OCID for Always Free)"
}

variable "tenancy_ocid" {
  type        = string
  description = "OCI tenancy OCID"
}

variable "region" {
  type        = string
  description = "OCI region (e.g. ap-mumbai-1)"
}

variable "ssh_pubkey" {
  type        = string
  description = "Contents of ~/.ssh/pier_ed25519.pub"
}

variable "operator_cidr" {
  type        = string
  description = "Operator home IP in CIDR notation (e.g. 1.2.3.4/32)"
}

variable "duckdns_root" {
  type        = string
  description = "Full DuckDNS domain (e.g. pier-yourname.duckdns.org)"
}

variable "duckdns_token" {
  type        = string
  sensitive   = true
  description = "DuckDNS account token UUID"
}

variable "repo_url" {
  type        = string
  description = "HTTPS URL of the Pier repo (e.g. https://github.com/adrianhallnew/pier.git)"
}
