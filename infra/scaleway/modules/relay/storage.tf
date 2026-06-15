resource "scaleway_object_bucket" "pool" {
  name       = "${local.name}-pool"
  region     = var.scw_region
  project_id = var.scw_project_id

  versioning {
    enabled = false
  }
}

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
