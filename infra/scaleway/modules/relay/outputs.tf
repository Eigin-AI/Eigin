output "service_url" {
  description = "Default Scaleway URL of the deployed relay container"
  value       = "https://${scaleway_container.relay.domain_name}"
}

output "registry_endpoint" {
  description = "Container registry endpoint (without trailing slash)"
  value       = "rg.${var.scw_region}.scw.cloud/${local.namespace}"
}

output "pool_bucket" {
  description = "S3 bucket name used for pool state"
  value       = scaleway_object_bucket.pool.name
}
