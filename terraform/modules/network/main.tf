locals {
  vpc_name    = "${var.name_prefix}-vpc"
  subnet_name = "${var.name_prefix}-subnet-${var.region}"
  router_name = "${var.name_prefix}-router-${var.region}"
  nat_name    = "${var.name_prefix}-nat-${var.region}"
  fw_iap_name = "${var.name_prefix}-allow-iap-ssh"
}

resource "google_compute_network" "this" {
  project                         = var.project_id
  name                            = local.vpc_name
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "this" {
  project                  = var.project_id
  name                     = local.subnet_name
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_10_MIN"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

resource "google_compute_router" "this" {
  project = var.project_id
  name    = local.router_name
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  project                            = var.project_id
  name                               = local.nat_name
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.this.id
    source_ip_ranges_to_nat = ["PRIMARY_IP_RANGE"]
  }

  log_config {
    enable = true
    filter = var.nat_log_filter
  }
}

resource "google_compute_firewall" "allow_iap_ssh" {
  project     = var.project_id
  name        = local.fw_iap_name
  network     = google_compute_network.this.name
  description = "Allow SSH (tcp/22) ingress from GCP Identity-Aware Proxy only, scoped to VMs tagged ${var.iap_ssh_tag}."
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = [var.iap_source_cidr]
  target_tags   = [var.iap_ssh_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
