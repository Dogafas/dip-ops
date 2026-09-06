output "master_external_ip" {
  value       = yandex_compute_instance.master.network_interface[0].nat_ip_address
  description = "Public IP address of Master/Bastion"
}

output "master_internal_ip" {
  value       = yandex_compute_instance.master.network_interface[0].ip_address
  description = "Private IP address of Master"
}

output "workers_internal_ips" {
  value       = { for k, v in yandex_compute_instance.workers : k => v.network_interface[0].ip_address }
  description = "Private IP addresses of Worker nodes"
}
