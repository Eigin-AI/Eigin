# Runbooks

Step-by-step operational procedures. Read the page through before starting, and rehearse
on staging first.

- [Token key rotation](./token-key-rotation.md) — rotate the key that encrypts credit
  tokens at rest. Includes a re-encryption sweep.
- [Relay key rotation](./relay-key-rotation.md) — rotate the `x-eigin-key` client gate.
- [Grant key rotation](./grant-key-rotation.md) — rotate the grant signing key.
- [Terraform remote state](./terraform-remote-state.md) — move Terraform state to a
  private, versioned bucket.
