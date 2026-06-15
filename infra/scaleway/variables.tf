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

# --- Inference proxy ---

variable "upstream_api_key" {
  description = "API key for the upstream inference provider"
  type        = string
  sensitive   = true
}

variable "upstream_api_url" {
  description = "Base URL for the upstream inference provider"
  type        = string

  validation {
    condition     = startswith(var.upstream_api_url, "https://") || startswith(var.upstream_api_url, "http://")
    error_message = "upstream_api_url must include an http:// or https:// scheme."
  }
}

variable "apple_bundle_id" {
  description = "Apple app bundle ID, e.g. ai.eigin.app"
  type        = string
  default     = ""
}

variable "apple_environment" {
  description = "Apple StoreKit environment: Sandbox or Production"
  type        = string
  default     = "Sandbox"
}

variable "apple_app_apple_id" {
  description = "Numeric Apple app ID (required in Production)"
  type        = string
  default     = ""
}

variable "grant_issuer" {
  description = "Expected issuer (iss) for credit grant tokens"
  type        = string
  default     = "eigin"
}

variable "admit_floor_credits" {
  description = "Minimum credits required to admit an inference request"
  type        = number
  default     = 50
}


variable "token_rate_limit_requests" {
  description = "Maximum inference completions per token per window"
  type        = number
  default     = 20
}

variable "token_rate_limit_window_seconds" {
  description = "Rate limit window in seconds for per-token limiting"
  type        = number
  default     = 60
}

