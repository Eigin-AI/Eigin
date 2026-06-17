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

output "eigin_relay_key" {
  description = "Generated x-eigin-key for this environment; configure clients with it"
  value       = random_password.eigin_relay_key.result
  sensitive   = true
}
