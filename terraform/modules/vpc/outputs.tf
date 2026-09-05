output "network_id" {
  value       = yandex_vpc_network.this.id
  description = "VPC network ID"
}

output "subnet_ids" {
  value       = { for k, v in yandex_vpc_subnet.this : k => v.id }
  description = "Map of subnet names to subnet IDs"
}