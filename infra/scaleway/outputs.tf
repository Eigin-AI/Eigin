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

output "token_encryption_key" {
  description = "Current token encryption key (base64). Read during a rotation to seed the secondary and feed the rotate-key sweep."
  value       = module.relay.token_encryption_key
  sensitive   = true
}

output "database_url" {
  description = "Relay database connection string. Used by the rotate-key tool during a token-key rotation."
  value       = module.relay.database_url
  sensitive   = true
}

output "assets_bucket" {
  description = "Name of the model-asset mirror bucket"
  value       = module.relay.assets_bucket
}

output "assets_write_access_key" {
  description = "Access key for the asset-upload identity (runbook use only)"
  value       = module.relay.assets_write_access_key
  sensitive   = true
}

output "assets_write_secret_key" {
  description = "Secret key for the asset-upload identity (runbook use only)"
  value       = module.relay.assets_write_secret_key
  sensitive   = true
}
