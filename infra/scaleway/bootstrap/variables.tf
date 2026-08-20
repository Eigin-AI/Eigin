variable "tfstate_project_name" {
  description = "Name of the dedicated Scaleway project that holds the state bucket"
  type        = string
  default     = "eigin-tfstate"
}

variable "tfstate_bucket_name" {
  description = "Optional override for the bucket name. Defaults to <project>-<random>."
  type        = string
  default     = null
}

variable "scw_region" {
  description = "Scaleway region for the state bucket"
  type        = string
  default     = "fr-par"
}
