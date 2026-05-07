variable "relay_src_dir" {
  description = "Absolute path to the eigin_relay source directory"
  type        = string
}

variable "project_name" {
  description = "Project name — used as a prefix for all resource names"
  type        = string
}

variable "scw_secret_key" {
  description = "Scaleway IAM secret key"
  type        = string
  sensitive   = true
}

variable "scw_project_id" {
  description = "Scaleway project ID"
  type        = string
}

variable "scw_region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "mojeek_api_key" {
  description = "Mojeek search API key"
  type        = string
  sensitive   = true
}

variable "eigin_relay_key" {
  description = "Shared auth key expected from Eigin clients"
  type        = string
  sensitive   = true
}

variable "monthly_pool_size" {
  description = "Monthly search quota cap"
  type        = number
  default     = 5000
}

variable "max_scale" {
  description = "Maximum number of container instances"
  type        = number
  default     = 3
}

