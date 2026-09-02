# Grant key rotation

Rotate the Ed25519 key the relay verifies credit grants against. Replacing it invalidates
grants signed with the old key, so re-issue any that must keep working.

`ENV` is `staging` or `production`. Prepare your shell first:

```sh
export ENV=staging
eval "$(cargo run -q --manifest-path tools/Cargo.toml -- config export tf-vars $ENV)"
cd infra/scaleway && terraform workspace select $ENV
```

## 1. Replace the keypair

```sh
terraform apply -replace=module.relay.tls_private_key.grant -var-file=environments/$ENV.tfvars
```

The relay now verifies against the new public key; grants signed with the old key stop
working.

## 2. Re-issue grants

Re-sign any grants that must keep working with the new key:

```sh
just grant sign
```
