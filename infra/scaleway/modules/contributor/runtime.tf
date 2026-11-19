variable "oauth" {
  type      = object({ client_id = string, client_secret = string })
  sensitive = true
}

locals {
  host = "contribute.eigin.ai"
}

resource "scaleway_container" "portal" {
  namespace_id   = scaleway_container_namespace.portal.id
  region         = var.region
  name           = "portal"
  registry_image = local.image
  deploy         = false
  privacy        = "private"
  http_option    = "redirected"
  min_scale      = 0
  max_scale      = 1
  port           = 8080
  memory_limit   = 560
  cpu_limit      = 560
  environment_variables = {
    ORIGIN              = "https://${local.host}"
    REVIEWER_GITLAB_IDS = "5"
    ADDRESS_HEADER      = "x-forwarded-for"
    XFF_DEPTH           = "1"
  }
  secret_environment_variables = {
    DATABASE_URL         = local.database_urls.runtime
    GITLAB_CLIENT_ID     = var.oauth.client_id
    GITLAB_CLIENT_SECRET = var.oauth.client_secret
  }
  health_check {
    http { path = "/healthz" }
    interval          = "10s"
    failure_threshold = 3
  }
  lifecycle {
    ignore_changes = [registry_image, privacy]
    precondition {
      condition     = var.oauth.client_id != "" && var.oauth.client_secret != ""
      error_message = "Configure production contributor OAuth credentials before creating the service."
    }
  }
}

resource "scaleway_job_definition" "portal" {
  for_each               = { migrate = "migration", prune = "runtime" }
  project_id             = scaleway_account_project.portal.id
  region                 = var.region
  name                   = "contributor-${each.key}"
  cpu_limit              = 560
  memory_limit           = 560
  local_storage_capacity = 1024
  timeout                = "5m"
  image_uri              = local.image
  startup_command        = ["node"]
  args                   = [each.key == "migrate" ? "scripts/migrate.ts" : "scripts/prune-oauth-attempts.ts"]
  secret_reference {
    secret_id   = scaleway_secret.database[each.value].id
    environment = "DATABASE_URL"
  }
  dynamic "cron" {
    for_each = each.key == "prune" ? [1] : []
    content {
      schedule = "17 3 * * *"
      timezone = "UTC"
    }
  }
  depends_on = [scaleway_secret_version.database, scaleway_iam_policy.database]
  lifecycle {
    ignore_changes = [image_uri]
  }
}

output "release" {
  value = {
    project  = scaleway_account_project.portal.id
    region   = var.region
    repo     = local.repo
    digest   = docker_registry_image.portal.sha256_digest
    hostname = scaleway_container.portal.domain_name
    service  = basename(scaleway_container.portal.id)
    migrate  = basename(scaleway_job_definition.portal["migrate"].id)
    prune    = basename(scaleway_job_definition.portal["prune"].id)
  }
}
