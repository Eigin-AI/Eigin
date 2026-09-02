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
    TRUSTED_PROXY_HOPS                = tostring(var.trusted_proxy_hops)
    WEBHOOK_RATE_LIMIT_REQUESTS       = tostring(var.webhook_rate_limit_requests)
    WEBHOOK_RATE_LIMIT_WINDOW_SECONDS = tostring(var.webhook_rate_limit_window_seconds)
    MODELS_CONFIG_PATH                = "/config/models.toml"
    PRODUCTS_CONFIG_PATH              = "/config/products.toml"
    PROVIDERS_CONFIG_PATH             = "/config/providers.toml"
    ASSETS_CONFIG_PATH                = "/config/assets.toml"
    S3_ENDPOINT                       = "https://s3.${var.scw_region}.scw.cloud"
    S3_REGION                         = var.scw_region
    PRESIGN_EXPIRY_SECONDS            = tostring(var.presign_expiry_seconds)

    # Plain logs: no ANSI codes, keeps LogQL substring matches and the
    # Grafana log view clean. tracing-subscriber honors NO_COLOR.
    NO_COLOR = "1"
  }

  # The relay always has a Terraform-generated primary key (both for the client gate and
  # for token encryption). Secondary keys are injected only during a rotation (when
  # supplied) so tokens/app builds carrying the previous key keep working; they are omitted
  # otherwise to avoid an empty secret.
  secret_environment_variables = merge(
    {
      MOJEEK_API_KEY               = var.mojeek_api_key
      EIGIN_RELAY_PRIMARY_KEY      = random_password.eigin_relay_key.result
      TOKEN_ENCRYPTION_KEY_PRIMARY = random_bytes.token_encryption_key.base64
      DATABASE_URL                 = local.database_url
      ASSETS_BUCKET                = scaleway_object_bucket.assets.name
      S3_ACCESS_KEY                = scaleway_iam_api_key.assets_read.access_key
      S3_SECRET_KEY                = scaleway_iam_api_key.assets_read.secret_key
    },
    var.eigin_relay_secondary_key != "" ? { EIGIN_RELAY_SECONDARY_KEY = var.eigin_relay_secondary_key } : {},
    var.token_encryption_secondary_key != "" ? { TOKEN_ENCRYPTION_KEY_SECONDARY = var.token_encryption_secondary_key } : {},
    {
      for name, key in var.provider_api_keys :
      "PROVIDER_${upper(name)}_API_KEY" => key
    }
  )

  depends_on = [
    docker_registry_image.relay,
    scaleway_sdb_sql_database.db,
    scaleway_iam_policy.db,
    scaleway_iam_policy.assets_read,
  ]
}
