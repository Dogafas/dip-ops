output "stage_network_id" {
  value       = module.vpc.network_id
  description = "Stage VPC ID"
}

output "stage_subnet_ids" {
  value       = module.vpc.subnet_ids
  description = "Stage Subnet IDs"
}

output "k8s_master_public_ip" {
  value       = module.k8s_cluster.master_external_ip
  description = "Master Bastion public IP"
}

output "k8s_master_internal_ip" {
  value       = module.k8s_cluster.master_internal_ip
  description = "Master internal IP"
}

output "k8s_workers_internal_ips" {
  value       = module.k8s_cluster.workers_internal_ips
  description = "Workers internal IPs"
}
