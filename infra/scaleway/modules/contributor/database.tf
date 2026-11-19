resource "scaleway_sdb_sql_database" "portal" {
  project_id = scaleway_account_project.portal.id
  region     = var.region
  name       = "contributors"
  min_cpu    = 0
  max_cpu    = 1

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  sql_permissions = {
    runtime   = "ServerlessSQLDatabaseDataReadWrite"
    migration = "ServerlessSQLDatabaseReadWrite"
  }
}

resource "scaleway_iam_application" "database" {
  for_each = local.sql_permissions
  name     = "${var.project_name}-${each.key}"
}

resource "scaleway_iam_policy" "database" {
  for_each       = local.sql_permissions
  name           = "${var.project_name}-${each.key}"
  application_id = scaleway_iam_application.database[each.key].id

  rule {
    project_ids          = [scaleway_account_project.portal.id]
    permission_set_names = [each.value]
  }
}

resource "scaleway_iam_api_key" "database" {
  for_each           = local.sql_permissions
  application_id     = scaleway_iam_application.database[each.key].id
  default_project_id = scaleway_account_project.portal.id
  expires_at         = timeadd(timestamp(), "8760h")
  lifecycle {
    ignore_changes = [expires_at]
  }
}

locals {
  endpoint = split("?", trimprefix(scaleway_sdb_sql_database.portal.endpoint, "postgres://"))[0]
  database_urls = { for role, key in scaleway_iam_api_key.database : role =>
    "postgresql://${scaleway_iam_application.database[role].id}:${urlencode(key.secret_key)}@${local.endpoint}?sslmode=verify-full"
  }
}

resource "scaleway_secret" "database" {
  for_each   = local.sql_permissions
  project_id = scaleway_account_project.portal.id
  region     = var.region
  name       = "contributor-db-${each.key}"
}

resource "scaleway_secret_version" "database" {
  for_each  = local.sql_permissions
  secret_id = scaleway_secret.database[each.key].id
  data      = local.database_urls[each.key]
}
