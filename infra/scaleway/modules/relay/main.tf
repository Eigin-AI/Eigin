# ---------------------------------------------------------------------------
# Container registry
# ---------------------------------------------------------------------------

resource "scaleway_registry_namespace" "relay" {
  name       = local.namespace
  region     = var.scw_region
  is_public  = false
  project_id = var.scw_project_id
}

# ---------------------------------------------------------------------------
# Docker image — built and pushed by the kreuzwerker/docker provider
# ---------------------------------------------------------------------------

resource "docker_image" "relay" {
  name = local.image_ref

  build {
    context    = var.relay_src_dir
    dockerfile = "Dockerfile"
    platform   = "linux/amd64"
  }

  keep_locally = false
}

resource "docker_registry_image" "relay" {
  name          = local.image_ref
  keep_remotely = true

  depends_on = [docker_image.relay]
}

# ---------------------------------------------------------------------------
# S3 bucket for pool state
# ---------------------------------------------------------------------------

resource "scaleway_object_bucket" "pool" {
  name       = "${local.name}-pool"
  region     = var.scw_region
  project_id = var.scw_project_id

  versioning {
    enabled = false
  }
}

# ---------------------------------------------------------------------------
# IAM — dedicated service account scoped to the pool bucket
# ---------------------------------------------------------------------------

resource "scaleway_iam_application" "pool" {
  name        = "${local.name}-pool"
  description = "Service account for the relay to read/write pool state in object storage."
}

resource "scaleway_iam_policy" "pool" {
  name           = "${local.name}-pool"
  description    = "Grants object read/write to the relay pool service account. Project-scoped — Scaleway IAM does not support bucket-level scoping."
  application_id = scaleway_iam_application.pool.id

  rule {
    project_ids          = [var.scw_project_id]
    permission_set_names = ["ObjectStorageBucketsRead", "ObjectStorageObjectsRead", "ObjectStorageObjectsWrite"]
  }
}

resource "scaleway_iam_api_key" "pool" {
  application_id     = scaleway_iam_application.pool.id
  description        = "S3 key for relay pool state bucket."
  default_project_id = var.scw_project_id
  expires_at         = timeadd(timestamp(), "8760h") # 1 year; set once, not updated on re-apply

  lifecycle {
    ignore_changes = [expires_at]
  }
}

# ---------------------------------------------------------------------------
# Serverless container namespace
# ---------------------------------------------------------------------------

resource "scaleway_container_namespace" "relay" {
  name       = local.name
  region     = var.scw_region
  project_id = var.scw_project_id
}

# ---------------------------------------------------------------------------
# Serverless container
# ---------------------------------------------------------------------------

resource "scaleway_container" "relay" {
  name         = local.name
  namespace_id = scaleway_container_namespace.relay.id
  region       = var.scw_region

  registry_image = local.image_ref
  deploy         = true
  port           = 8080
  min_scale      = 0
  max_scale      = var.max_scale
  memory_limit   = 280
  cpu_limit      = 280 # mVCPU

  privacy     = "public"
  http_option = "redirected"

  environment_variables = {
    SEARCH_API_URL    = "https://api.mojeek.com"
    MONTHLY_POOL_SIZE = tostring(var.monthly_pool_size)
    POOL_BUCKET       = scaleway_object_bucket.pool.name
    POOL_OBJECT_KEY   = "pool.json"
    S3_ENDPOINT       = local.s3_endpoint
  }

  secret_environment_variables = {
    MOJEEK_API_KEY  = var.mojeek_api_key
    EIGIN_RELAY_KEY = var.eigin_relay_key
    S3_ACCESS_KEY   = scaleway_iam_api_key.pool.access_key
    S3_SECRET_KEY   = scaleway_iam_api_key.pool.secret_key
  }

  depends_on = [
    docker_registry_image.relay,
    scaleway_object_bucket.pool,
    scaleway_iam_policy.pool,
  ]
}

