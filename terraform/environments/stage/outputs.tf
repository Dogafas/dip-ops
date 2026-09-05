output "stage_network_id" {
  value       = module.vpc.network_id
  description = "Stage VPC ID"
}

output "stage_subnet_ids" {
  value       = module.vpc.subnet_ids
  description = "Stage Subnet IDs"
}
