module "network" {
  source = "../../modules/network"

  project_id       = var.project_id
  region           = var.region
  name_prefix      = var.name_prefix
  subnet_cidr      = var.subnet_cidr
  enable_flow_logs = var.enable_flow_logs
  nat_log_filter   = var.nat_log_filter
  labels           = var.labels
}
