# Model-asset mirror: private bucket serving versioned model assets to the app
# via GET /v1/assets. Lives in the relay module — only the relay reads it, the
# same way the database does.

# Bucket layout: assets/{id}/{version}/…files… + a manifest.json per version.
# Immutability of a released version rests on three things: the sha-pinned
# pointer in assets.toml (git-reviewed), the uploader's create-only puts (no
# overwrites), and versioning — a rewrite makes a new version, it can't mutate
# an existing one. Object lock is enabled only to turn versioning on; we set no
# default retention because deletion is already controlled by IAM: the relay is
# read-only and nothing but the runbook-only write identity can delete.
resource "scaleway_object_bucket" "assets" {
  name                = "${local.name}-assets"
  region              = var.scw_region
  project_id          = var.scw_project_id
  object_lock_enabled = true
}

# Read identity — the relay reads manifests and presigns downloads. GET only.
resource "scaleway_iam_application" "assets_read" {
  name        = "${local.name}-assets-read"
  description = "Relay read access to the model-asset mirror bucket."
}

resource "scaleway_iam_api_key" "assets_read" {
  application_id     = scaleway_iam_application.assets_read.id
  description        = "IAM key for reading model assets."
  default_project_id = var.scw_project_id
  expires_at         = timeadd(timestamp(), "8760h") # 1 year; set once, not updated on re-apply

  lifecycle {
    ignore_changes = [expires_at]
  }
}

resource "scaleway_iam_policy" "assets_read" {
  name           = "${local.name}-assets-read"
  description    = "Grants object read on the asset bucket to the relay read identity."
  application_id = scaleway_iam_application.assets_read.id

  rule {
    project_ids          = [var.scw_project_id]
    permission_set_names = ["ObjectStorageObjectsRead"]
  }
}

# Write identity for `eigin-tools assets upload`. Read (to skip already-present
# files), write (upload), and delete (surgically remove a bad version before
# re-uploading). Runbook-only: never deployed, never held by the relay.
resource "scaleway_iam_application" "assets_write" {
  name        = "${local.name}-assets-write"
  description = "Upload access for the model-asset mirror bucket. Runbook-only, never deployed."
}

resource "scaleway_iam_api_key" "assets_write" {
  application_id     = scaleway_iam_application.assets_write.id
  description        = "IAM key for uploading model assets."
  default_project_id = var.scw_project_id
  expires_at         = timeadd(timestamp(), "8760h") # 1 year; set once, not updated on re-apply

  lifecycle {
    ignore_changes = [expires_at]
  }
}

resource "scaleway_iam_policy" "assets_write" {
  name           = "${local.name}-assets-write"
  description    = "Grants object read/write/delete on the asset bucket to the upload identity."
  application_id = scaleway_iam_application.assets_write.id

  rule {
    project_ids = [var.scw_project_id]
    permission_set_names = [
      "ObjectStorageObjectsRead",
      "ObjectStorageObjectsWrite",
      "ObjectStorageObjectsDelete",
    ]
  }
}
