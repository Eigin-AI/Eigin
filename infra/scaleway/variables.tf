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

variable "alerts_email" {
  description = "Where Cockpit sends alert emails. Supplied via .env (EIGIN_ALERTS_EMAIL, falling back to EIGIN_SUPPORT_EMAIL) through tf-vars."
  type        = string
  default     = "support@eigin.ai"
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

variable "provider_api_keys" {
  description = "Map of provider ID -> API key for upstream inference providers"
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "apple_bundle_id" {
  description = "Comma-separated set of accepted Apple bundle IDs, e.g. ai.eigin.finch or com.42futures.carrel,ai.eigin.finch during migration"
  type        = string
  default     = ""
}

variable "apple_environments" {
  description = "Apple StoreKit environments to accept, e.g. [\"Sandbox\"] or [\"Production\", \"Sandbox\"]"
  type        = list(string)
  default     = ["Sandbox"]

  validation {
    condition     = length(var.apple_environments) > 0 && alltrue([for e in var.apple_environments : contains(["Production", "Sandbox"], e)])
    error_message = "apple_environments must be a non-empty list of \"Production\" and/or \"Sandbox\"."
  }
}

variable "apple_app_apple_id" {
  description = "Numeric Apple app ID (required in Production)"
  type        = string
  default     = ""
}

variable "sandbox_monthly_credit_budget" {
  description = "Max credits issued to Sandbox (TestFlight/App Review) purchases per rolling window. Bounds free-credit abuse cost."
  type        = number
  default     = 25000
}

variable "eigin_relay_secondary_key" {
  description = "Optional previous relay key to keep accepting during a rotation. Empty disables it. Supplied via .env (EIGIN_RELAY_SECONDARY_KEY_<ENV>) through tf-vars."
  type        = string
  sensitive   = true
  default     = ""
}

variable "token_encryption_secondary_key" {
  description = "Optional previous token encryption key, set only during a token-key rotation so the relay can decrypt tokens minted under the old key. Empty disables it. Supplied via .env (TOKEN_ENCRYPTION_SECONDARY_KEY_<ENV>) through tf-vars."
  type        = string
  sensitive   = true
  default     = ""
}

variable "grant_issuer" {
  description = "Expected issuer (iss) for credit grant tokens"
  type        = string
  default     = "eigin"
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

variable "ip_rate_limit_requests" {
  description = "Maximum requests per client IP per window, applied as a blanket layer to every gated route"
  type        = number
  default     = 40
}

variable "ip_rate_limit_window_seconds" {
  description = "Rate limit window in seconds for per-IP limiting"
  type        = number
  default     = 60
}

variable "trusted_proxy_hops" {
  description = "Number of trusted proxy hops in front of the app, used to read the client IP from X-Forwarded-For. 1 behind Scaleway's ingress; verify empirically before changing."
  type        = number
  default     = 1
}

variable "webhook_rate_limit_requests" {
  description = "Maximum Apple webhook requests per IP per window"
  type        = number
  default     = 20
}

variable "webhook_rate_limit_window_seconds" {
  description = "Rate limit window in seconds for the Apple webhook"
  type        = number
  default     = 60
}

# --- Model-asset mirror ---

variable "presign_expiry_seconds" {
  description = "How long presigned asset download URLs stay valid (default 24h)"
  type        = number
  default     = 86400
}

