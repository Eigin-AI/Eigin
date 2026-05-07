output "project_id" {
  description = "Scaleway project ID created by Terraform"
  value       = scaleway_account_project.eigin.id
}

output "service_url" {
  description = "Public URL of the deployed relay container"
  value       = module.relay.service_url
}

output "registry_endpoint" {
  description = "Container registry endpoint"
  value       = module.relay.registry_endpoint
}

output "pool_bucket" {
  description = "S3 bucket name used for pool state"
  value       = module.relay.pool_bucket
}
