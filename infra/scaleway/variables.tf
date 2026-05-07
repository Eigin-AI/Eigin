variable "project_name" {
  description = "Scaleway project name — used to name the project and all resources"
  type        = string
  default     = "eigin-staging"
}

variable "scw_secret_key" {
  description = "Scaleway IAM secret key — used only for Docker registry auth. Read from scw CLI: $(scw config get secret-key)"
  type        = string
  sensitive   = true
}

variable "scw_region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "relay_src_dir" {
  description = "Path to the eigin_relay source directory, relative to the Terraform root"
  type        = string
  default     = "../../src/eigin_relay"
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

