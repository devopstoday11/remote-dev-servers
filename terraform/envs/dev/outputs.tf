output "vpc_name" {
  description = "VPC name."
  value       = module.network.vpc_name
}

output "subnet_name" {
  description = "Subnet name."
  value       = module.network.subnet_name
}

output "subnet_self_link" {
  description = "Subnet self link (passed to instance network_interface in Phase 2)."
  value       = module.network.subnet_self_link
}

output "subnet_cidr" {
  description = "Subnet primary IPv4 CIDR."
  value       = module.network.subnet_cidr
}

output "router_name" {
  description = "Cloud Router name."
  value       = module.network.router_name
}

output "nat_name" {
  description = "Cloud NAT name."
  value       = module.network.nat_name
}

output "iap_ssh_tag" {
  description = "Network tag a VM must carry to receive IAP SSH ingress."
  value       = module.network.iap_ssh_tag
}
