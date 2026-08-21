resource "scaleway_account_project" "eigin" {
  name = var.project_name
}

module "relay" {
  source = "./modules/relay"

  relay_src_dir     = "${path.root}/${var.relay_src_dir}"
  project_name      = var.project_name
  scw_secret_key    = var.scw_secret_key
  scw_project_id    = scaleway_account_project.eigin.id
  scw_region        = var.scw_region
  mojeek_api_key    = var.mojeek_api_key
  monthly_pool_size = var.monthly_pool_size
  max_scale         = var.max_scale

  # Inference proxy — provider API keys map provider IDs to their keys
  provider_api_keys = var.provider_api_keys

  apple_bundle_id                   = var.apple_bundle_id
  apple_environments                = var.apple_environments
  apple_app_apple_id                = var.apple_app_apple_id
  sandbox_monthly_credit_budget     = var.sandbox_monthly_credit_budget
  eigin_relay_secondary_key         = var.eigin_relay_secondary_key
  token_encryption_secondary_key    = var.token_encryption_secondary_key
  grant_issuer                      = var.grant_issuer
  admit_floor_credits               = var.admit_floor_credits
  token_rate_limit_requests         = var.token_rate_limit_requests
  token_rate_limit_window_seconds   = var.token_rate_limit_window_seconds
  ip_rate_limit_requests            = var.ip_rate_limit_requests
  ip_rate_limit_window_seconds      = var.ip_rate_limit_window_seconds
  trusted_proxy_hops                = var.trusted_proxy_hops
  webhook_rate_limit_requests       = var.webhook_rate_limit_requests
  webhook_rate_limit_window_seconds = var.webhook_rate_limit_window_seconds
}
