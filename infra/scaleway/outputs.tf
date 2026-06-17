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

output "grant_private_key_pem" {
  description = "Ed25519 private key (PEM) for signing credit grants in this environment"
  value       = module.relay.grant_private_key_pem
  sensitive   = true
}

output "eigin_relay_primary_key" {
  description = "Generated primary x-eigin-key for this environment; configure clients with it"
  value       = module.relay.eigin_relay_primary_key
  sensitive   = true
}
