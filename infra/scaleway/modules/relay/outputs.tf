output "service_url" {
  description = "Default Scaleway URL of the deployed relay container"
  value       = "https://${scaleway_container.relay.domain_name}"
}

output "registry_endpoint" {
  description = "Container registry endpoint (without trailing slash)"
  value       = "rg.${var.scw_region}.scw.cloud/${local.namespace}"
}

output "grant_private_key_pem" {
  description = "Ed25519 private key (PEM) for signing credit grants in this environment"
  value       = tls_private_key.grant.private_key_pem
  sensitive   = true
}

output "eigin_relay_primary_key" {
  description = "Generated primary x-eigin-key for this environment; configure clients with it"
  value       = random_password.eigin_relay_key.result
  sensitive   = true
}

output "token_encryption_key" {
  description = "Current token encryption key (base64). Read during a rotation to seed the secondary and feed the rotate-key sweep."
  value       = random_bytes.token_encryption_key.base64
  sensitive   = true
}

output "database_url" {
  description = "Relay database connection string. Used by the rotate-key tool during a token-key rotation."
  value       = local.database_url
  sensitive   = true
}

output "assets_bucket" {
  description = "Name of the model-asset mirror bucket"
  value       = scaleway_object_bucket.assets.name
}

output "assets_write_access_key" {
  description = "Access key for the asset-upload identity (runbook use only)"
  value       = scaleway_iam_api_key.assets_write.access_key
  sensitive   = true
}

output "assets_write_secret_key" {
  description = "Secret key for the asset-upload identity (runbook use only)"
  value       = scaleway_iam_api_key.assets_write.secret_key
  sensitive   = true
}
