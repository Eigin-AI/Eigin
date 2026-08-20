# Bootstrap root — provisions the home for the relay's remote Terraform state.
#
# This is a standalone root, applied once with local state before the main root
# migrates onto the bucket it creates (a bucket can't store the state that
# defines it). It lives in its own project so relay CI never needs credentials
# into unrelated internal infrastructure. See the runbook:
# docs/src/runbooks/terraform-remote-state.md

# Dedicated project — its only purpose is to hold the state bucket, so a
# project-scoped credential is effectively bucket-scoped.
resource "scaleway_account_project" "tfstate" {
  name = var.tfstate_project_name
}

# Bucket names are globally unique. Derive one from the project name plus a
# stable random suffix so no name has to be supplied by hand. An explicit
# tfstate_bucket_name overrides it.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  tfstate_bucket_name = coalesce(
    var.tfstate_bucket_name,
    "${var.tfstate_project_name}-${random_id.bucket_suffix.hex}",
  )
}

# Versioned bucket. Scaleway buckets are private by default (ACLs are disabled),
# so no ACL resource is needed. prevent_destroy guards against tearing down the
# store that holds every environment's state.
resource "scaleway_object_bucket" "tfstate" {
  name       = local.tfstate_bucket_name
  region     = var.scw_region
  project_id = scaleway_account_project.tfstate.id

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Scoped credential: object access limited to the tfstate project only, so it
# can reach the state bucket and nothing else.
resource "scaleway_iam_application" "tfstate" {
  name        = "eigin-tfstate"
  description = "Service account for reading/writing the relay's remote Terraform state."
}

resource "scaleway_iam_policy" "tfstate" {
  name           = "eigin-tfstate"
  description    = "Grants Object Storage access to the dedicated Terraform state project only."
  application_id = scaleway_iam_application.tfstate.id

  rule {
    project_ids          = [scaleway_account_project.tfstate.id]
    permission_set_names = ["ObjectStorageFullAccess"]
  }
}

resource "scaleway_iam_api_key" "tfstate" {
  application_id     = scaleway_iam_application.tfstate.id
  description        = "IAM key for the S3 remote-state backend."
  default_project_id = scaleway_account_project.tfstate.id
  expires_at         = timeadd(timestamp(), "8760h") # 1 year; set once, not updated on re-apply

  lifecycle {
    ignore_changes = [expires_at]
  }
}
