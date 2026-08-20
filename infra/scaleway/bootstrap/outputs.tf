output "tfstate_bucket_name" {
  description = "Bucket name — set this as `bucket` in the main root's backend.tf"
  value       = scaleway_object_bucket.tfstate.name
}

output "tfstate_region" {
  description = "Bucket region — set this as `region` in backend.tf and TFSTATE_REGION in .env"
  value       = var.scw_region
}

output "tfstate_access_key" {
  description = "Scoped access key — set as TFSTATE_ACCESS_KEY in the repo-root .env"
  value       = scaleway_iam_api_key.tfstate.access_key
}

output "tfstate_secret_key" {
  description = "Scoped secret key — set as TFSTATE_SECRET_KEY in .env. Read with: terraform output -raw tfstate_secret_key"
  value       = scaleway_iam_api_key.tfstate.secret_key
  sensitive   = true
}
