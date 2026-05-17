variable "project_id" {
  description = "GCP project ID where the network resources will be created."
  type        = string
}

variable "region" {
  description = "GCP region for the regional subnet, Cloud Router, and Cloud NAT."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to every resource name created by the module."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2-32 chars, lowercase, start with a letter, end with a letter or digit."
  }
}

variable "subnet_cidr" {
  description = "Primary IPv4 CIDR for the regional subnet."
  type        = string
  default     = "10.0.0.0/24"
}

variable "iap_source_cidr" {
  description = "Source CIDR for GCP Identity-Aware Proxy. Do not change unless Google updates the published range."
  type        = string
  default     = "35.235.240.0/20"
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs on the subnet. Adds cost; default off."
  type        = bool
  default     = false
}

variable "nat_log_filter" {
  description = "Cloud NAT logging filter: ERRORS_ONLY, TRANSLATIONS_ONLY, or ALL."
  type        = string
  default     = "ERRORS_ONLY"

  validation {
    condition     = contains(["ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL"], var.nat_log_filter)
    error_message = "nat_log_filter must be ERRORS_ONLY, TRANSLATIONS_ONLY, or ALL."
  }
}

variable "iap_ssh_tag" {
  description = "Network tag a VM must carry to receive IAP SSH ingress."
  type        = string
  default     = "iap-ssh"
}

variable "labels" {
  description = "Labels applied to resources that support them."
  type        = map(string)
  default     = {}
}
