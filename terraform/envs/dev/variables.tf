variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix applied to every resource name in this env."
  type        = string
  default     = "remote-dev"
}

variable "subnet_cidr" {
  description = "Primary IPv4 CIDR for the regional subnet."
  type        = string
  default     = "10.0.0.0/24"
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs on the subnet."
  type        = bool
  default     = false
}

variable "nat_log_filter" {
  description = "Cloud NAT log filter: ERRORS_ONLY, TRANSLATIONS_ONLY, or ALL."
  type        = string
  default     = "ERRORS_ONLY"
}

variable "labels" {
  description = "Labels applied to resources that support them."
  type        = map(string)
  default = {
    managed-by = "terraform"
    env        = "dev"
    repo       = "remote-dev-servers"
  }
}
