# Relay key rotation

Rotate the `x-eigin-key` client gate. It encrypts no stored data, so there's nothing to
migrate — the relay accepts a generated primary plus, during a rotation, an old secondary
so already-shipped app builds keep working. Old builds age out.

`ENV` is `staging` or `production`. Prepare your shell first:

```sh
export ENV=staging
eval "$(cargo run -q --manifest-path tools/Cargo.toml -- config export tf-vars $ENV)"
cd infra/scaleway && terraform workspace select $ENV
```

## 1. Keep the current key as fallback

Read it and add it to the repo-root `.env` as `EIGIN_RELAY_SECONDARY_KEY_<ENV>`:

```sh
terraform output -raw eigin_relay_primary_key
```

## 2. Generate a new primary

```sh
eval "$(cargo run -q --manifest-path tools/Cargo.toml -- config export tf-vars $ENV)"
terraform apply -replace=module.relay.random_password.eigin_relay_key -var-file=environments/$ENV.tfvars
terraform output -raw eigin_relay_primary_key   # ship this in new app builds
```

## 3. Retire the old key

Once old builds have aged out, remove `EIGIN_RELAY_SECONDARY_KEY_<ENV>` from `.env` and
redeploy:

```sh
just infra deploy $ENV
```
