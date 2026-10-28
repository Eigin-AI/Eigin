# The publisher can write website content, never the shared state bucket.
resource "scaleway_iam_application" "publisher" {
  name = "${var.project_name}-publisher"
}

resource "scaleway_iam_policy" "publisher" {
  name           = "${var.project_name}-publisher"
  application_id = scaleway_iam_application.publisher.id
  rule {
    project_ids          = [scaleway_account_project.website.id]
    permission_set_names = ["ObjectStorageFullAccess"]
  }
}

resource "scaleway_iam_api_key" "publisher" {
  application_id     = scaleway_iam_application.publisher.id
  default_project_id = scaleway_account_project.website.id
  description        = "Website content publishing only."
  expires_at         = timeadd(timestamp(), "8760h")
  lifecycle {
    ignore_changes = [expires_at]
  }
  depends_on = [scaleway_iam_policy.publisher]
}

output "upload_access_key" {
  description = "Publisher access key; consumed in memory by the website CLI."
  value       = scaleway_iam_api_key.publisher.access_key
  sensitive   = true
}
output "upload_secret_key" {
  description = "Publisher secret key; consumed in memory by the website CLI."
  value       = scaleway_iam_api_key.publisher.secret_key
  sensitive   = true
}
