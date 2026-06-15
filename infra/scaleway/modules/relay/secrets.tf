# Secrets that are ours to mint are generated and owned by Terraform, stored in state
# (one independent set per workspace). External secrets a human must supply (provider
# API keys) come from .env via variables; non-secret config lives in
# environments/*.tfvars. Neither of those belongs here.

# Token encryption key — 32 random bytes (base64-encoded for the relay).
resource "random_bytes" "token_encryption_key" {
  length = 32
}

# Relay API key — the shared `x-eigin-key` gate. Read it for clients with:
#   terraform output -raw eigin_relay_key
resource "random_password" "eigin_relay_key" {
  length  = 32
  special = false
}

# Grant signing keypair — verifies credit grants. The public key goes to the relay; the
# private key is a sensitive output for the signing faucet. Rotate by replacing it:
#   terraform apply -replace=module.relay.tls_private_key.grant
resource "tls_private_key" "grant" {
  algorithm = "ED25519"
}
