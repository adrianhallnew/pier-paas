output "vm_public_ip" {
  value       = oci_core_public_ip.pier.ip_address
  description = "Reserved public IP of the Pier VM"
}

output "ssh_command" {
  value       = "ssh pier@${oci_core_public_ip.pier.ip_address}"
  description = "SSH command to connect to the Pier VM"
}
