output "vpc_id" {
  description = "Fully-qualified VPC ID."
  value       = google_compute_network.this.id
}

output "vpc_name" {
  description = "VPC name."
  value       = google_compute_network.this.name
}

output "vpc_self_link" {
  description = "VPC self link."
  value       = google_compute_network.this.self_link
}

output "subnet_id" {
  description = "Fully-qualified subnet ID."
  value       = google_compute_subnetwork.this.id
}

output "subnet_name" {
  description = "Subnet name."
  value       = google_compute_subnetwork.this.name
}

output "subnet_self_link" {
  description = "Subnet self link (used by instance network_interface)."
  value       = google_compute_subnetwork.this.self_link
}

output "subnet_cidr" {
  description = "Subnet primary IPv4 CIDR."
  value       = google_compute_subnetwork.this.ip_cidr_range
}

output "router_name" {
  description = "Cloud Router name."
  value       = google_compute_router.this.name
}

output "nat_name" {
  description = "Cloud NAT name."
  value       = google_compute_router_nat.this.name
}

output "iap_ssh_tag" {
  description = "Network tag a VM must carry to receive IAP SSH ingress."
  value       = var.iap_ssh_tag
}
