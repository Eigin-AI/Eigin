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

  # Inference proxy — set real values in .env / tfvars before deploying
  upstream_api_key                = var.upstream_api_key
  upstream_api_url                = var.upstream_api_url
  apple_bundle_id                 = var.apple_bundle_id
  apple_environment               = var.apple_environment
  apple_app_apple_id              = var.apple_app_apple_id
  grant_issuer                    = var.grant_issuer
  admit_floor_credits             = var.admit_floor_credits
  token_rate_limit_requests       = var.token_rate_limit_requests
  token_rate_limit_window_seconds = var.token_rate_limit_window_seconds
}
