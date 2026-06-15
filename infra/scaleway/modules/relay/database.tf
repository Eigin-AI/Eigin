resource "scaleway_sdb_sql_database" "db" {
  name       = "${local.name}-db"
  region     = var.scw_region
  project_id = var.scw_project_id
  min_cpu    = 0
  max_cpu    = 4
}

resource "scaleway_iam_application" "db" {
  name        = "${local.name}-db"
  description = "Service account for the relay to read/write its database."
}

resource "scaleway_iam_policy" "db" {
  name           = "${local.name}-db"
  description    = "Grants Serverless SQL Database read/write to the relay database service account."
  application_id = scaleway_iam_application.db.id

  rule {
    project_ids          = [var.scw_project_id]
    permission_set_names = ["ServerlessSQLDatabaseReadWrite"]
  }
}

resource "scaleway_iam_api_key" "db" {
  application_id     = scaleway_iam_application.db.id
  description        = "IAM key for relay database."
  default_project_id = var.scw_project_id
  expires_at         = timeadd(timestamp(), "8760h") # 1 year; set once, not updated on re-apply

  lifecycle {
    ignore_changes = [expires_at]
  }
}
