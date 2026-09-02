# Database key rotation

Rotate the IAM key the relay authenticates to its Serverless SQL database with. The key
has a one-year expiry that's set once at creation and never moves, so rotate it before the
year is up — when it lapses the relay silently loses its database connection.

Replacing the key both mints a fresh secret and resets the expiry to a new year. There's
no data to migrate and no dual-key window: the key encrypts nothing, it's only the
database credential.

`ENV` is `staging` or `production`. Prepare your shell first:

```sh
export ENV=staging
eval "$(cargo run -q --manifest-path tools/Cargo.toml -- config export tf-vars $ENV)"
cd infra/scaleway && terraform workspace select $ENV
```

## 1. Replace the key

```sh
terraform apply -replace=module.relay.scaleway_iam_api_key.db -var-file=environments/$ENV.tfvars
```

`DATABASE_URL` derives from the key, so the same apply reconnects the container on the new
credential. The expiry is now reset to a year out.
