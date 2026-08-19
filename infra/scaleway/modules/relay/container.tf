resource "scaleway_container_namespace" "relay" {
  name       = local.name
  region     = var.scw_region
  project_id = var.scw_project_id
}

resource "scaleway_container" "relay" {
  name         = local.name
  namespace_id = scaleway_container_namespace.relay.id
  region       = var.scw_region

  registry_image = local.image_ref
  deploy         = true
  port           = 8080
  min_scale      = 0
  max_scale      = var.max_scale
  memory_limit   = 560
  cpu_limit      = 560

  privacy     = "public"
  http_option = "redirected"

  environment_variables = {
    SEARCH_API_URL                    = "https://api.mojeek.com"
    MONTHLY_POOL_SIZE                 = tostring(var.monthly_pool_size)
    APPLE_ENVIRONMENTS                = join(",", var.apple_environments)
    APPLE_APP_APPLE_ID                = var.apple_app_apple_id
    APPLE_BUNDLE_ID                   = var.apple_bundle_id
    SANDBOX_MONTHLY_CREDIT_BUDGET     = tostring(var.sandbox_monthly_credit_budget)
    GRANT_PUBLIC_KEY                  = tls_private_key.grant.public_key_pem
    GRANT_ISSUER                      = var.grant_issuer
    ADMIT_FLOOR_CREDITS               = tostring(var.admit_floor_credits)
    TOKEN_RATE_LIMIT_REQUESTS         = tostring(var.token_rate_limit_requests)
    TOKEN_RATE_LIMIT_WINDOW_SECONDS   = tostring(var.token_rate_limit_window_seconds)
    RATE_LIMIT_REQUESTS               = tostring(var.ip_rate_limit_requests)
    RATE_LIMIT_WINDOW_SECONDS         = tostring(var.ip_rate_limit_window_seconds)
    WEBHOOK_RATE_LIMIT_REQUESTS       = tostring(var.webhook_rate_limit_requests)
    WEBHOOK_RATE_LIMIT_WINDOW_SECONDS = tostring(var.webhook_rate_limit_window_seconds)
    MODELS_CONFIG_PATH                = "/config/models.toml"
    PRODUCTS_CONFIG_PATH              = "/config/products.toml"
    PROVIDERS_CONFIG_PATH             = "/config/providers.toml"
  }

  # The relay always has a Terraform-generated primary key. A secondary key is
  # injected only during a rotation (when supplied) so already-shipped app builds
  # carrying the previous key keep working; omit it otherwise to avoid an empty secret.
  secret_environment_variables = merge(
    {
      MOJEEK_API_KEY          = var.mojeek_api_key
      EIGIN_RELAY_PRIMARY_KEY = random_password.eigin_relay_key.result
      TOKEN_ENCRYPTION_KEY    = random_bytes.token_encryption_key.base64
      DATABASE_URL            = "postgresql://${scaleway_iam_application.db.id}:${scaleway_iam_api_key.db.secret_key}@${trimprefix(scaleway_sdb_sql_database.db.endpoint, "postgres://")}"
    },
    var.eigin_relay_secondary_key != "" ? { EIGIN_RELAY_SECONDARY_KEY = var.eigin_relay_secondary_key } : {},
    {
      for name, key in var.provider_api_keys :
      "PROVIDER_${upper(name)}_API_KEY" => key
    }
  )

  depends_on = [
    docker_registry_image.relay,
    scaleway_sdb_sql_database.db,
    scaleway_iam_policy.db,
  ]
}
