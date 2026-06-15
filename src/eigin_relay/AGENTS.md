# Eigin Relay
Rust, Axum 0.8, Tower, Tokio.

The relay provides connectivity services that can't be bundled into the app — primarily proxying search APIs (Mojeek) while managing a community pool of shared API quota. It also enforces per-IP rate limiting and authenticates requests from Eigin clients.

Going forward, this is the intended home for agent synchronisation and agent-to-agent discovery. Neither is implemented yet.

## Project structure

```
src/
  main.rs         — server setup, env config, router
  lib.rs          — public API
  auth/           — authentication and request identity
    key.rs        — EIGIN_RELAY_KEY middleware
    bearer.rs     — Bearer-token extractor (credit token → wallet lookup)
  rate_limit.rs   — sliding window rate limiter, generic over key type (IpAddr or Uuid)
  state.rs        — shared AppState (Arc)
  health.rs       — health check handler
  error.rs        — AppError type (OpenAI-compatible JSON error body)
  search/         — search proxy (client, handler, pool, connection pool)
    pool/
      backend.rs  — PoolBackend trait, PoolState, BackendError
      file.rs     — local file backend (dev / single-instance)
      s3.rs       — S3-compatible backend with SigV4 signing + ETag optimistic locking
      state.rs    — Pool, PoolConfig, PoolConfig::from_env()
  credits/        — credit system (tokens, ledger, Apple verification, HTTP handlers)
    mod.rs        — public exports
    token.rs      — token generation (eict_ prefix), SHA-256 hashing, AEAD at-rest encryption
    ledger.rs     — CreditLedger trait + types (Wallet, WalletOrigin, WalletStatus)
    memory.rs     — InMemoryLedger (tests / dev)
    postgres.rs   — PostgresLedger (sqlx, runs migrations on startup)
    apple.rs      — AppleVerifier trait + AppStoreVerifier (app-store-server-library) + fake module
    redeem.rs     — POST /credits/redeem (purchase + idempotent restore)
    balance.rs    — GET /credits/balance
    webhook.rs    — POST /webhooks/apple/appstore (App Store Server Notifications V2)
  inference/      — OpenAI-compatible inference proxy with credit metering
    mod.rs        — public exports
    catalog.rs    — models.toml + products.toml loading + GET /v1/models
    rates.rs      — usage → millicredits cost computation
    usage.rs      — SSE/JSON usage-block extraction (never touches content)
    upstream.rs   — UpstreamClient trait + reqwest impl
    handler.rs    — POST /v1/chat/completions (admit, stream, settle)
migrations/
  0001_create_wallets.sql
  0002_create_processed_notifications.sql
config/
  models.toml     — curated model catalog + credit rates (TODO: pin to provider)
  products.toml   — IAP product credit tiers (TODO: pin to App Store products before launch)
  apple/          — Apple Root CA .cer files (DER-encoded, public certs, safe to commit)
tests/
  integration.rs  — search integration tests (httpmock)
  credits.rs      — end-to-end credit lifecycle tests (InMemoryLedger + FakeVerifier)
```

## Prerequisites

- Rust and Cargo via [rustup](https://rustup.rs)

## Configuration

All configuration is via environment variables:

### Search

| Variable | Default | Description |
|---|---|---|
| `MOJEEK_API_KEY` | required | Upstream search API key |
| `EIGIN_RELAY_KEY` | required | Shared auth key expected from Eigin clients |
| `SEARCH_API_URL` | `https://api.mojeek.com` | Upstream search base URL |
| `RATE_LIMIT_REQUESTS` | `10` | Max requests per window per IP |
| `RATE_LIMIT_WINDOW_SECONDS` | `60` | Rate limit window duration |
| `MONTHLY_POOL_SIZE` | `5000` | Monthly quota cap |
| `POOL_FILE_PATH` | — | Path to a local JSON file for pool state (single-instance only) |
| `POOL_BUCKET` | — | S3 bucket name for pool state (takes precedence over `POOL_FILE_PATH`) |
| `POOL_OBJECT_KEY` | `pool.json` | Object key within the S3 bucket |
| `S3_ENDPOINT` | required if `POOL_BUCKET` set | S3-compatible endpoint URL |
| `S3_ACCESS_KEY` | required if `POOL_BUCKET` set | S3 access key |
| `S3_SECRET_KEY` | required if `POOL_BUCKET` set | S3 secret key |
| `PORT` | `8080` | Listen port |

If neither `POOL_BUCKET` nor `POOL_FILE_PATH` is set, the pool runs in-memory (resets on restart).

### Credits and inference

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | — | Postgres connection string. If unset, uses `InMemoryLedger` (dev only, logs a warning). |
| `TOKEN_ENCRYPTION_KEY` | — | 32-byte base64url AEAD key for encrypting credit tokens at rest. Generate with `openssl rand -base64 32`. |
| `UPSTREAM_API_URL` | — | Base URL of the upstream inference provider. If unset, inference routes return 503. |
| `UPSTREAM_API_KEY` | — | API key for the upstream inference provider. |
| `APPLE_BUNDLE_ID` | — | App bundle ID, e.g. `ai.eigin.app`. |
| `APPLE_ENVIRONMENT` | `Sandbox` | `Sandbox` (staging) or `Production`. |
| `APPLE_APP_APPLE_ID` | — | Numeric App Store app ID. Required in Production. |
| `MODELS_CONFIG_PATH` | `config/models.toml` | Path to the model catalog TOML. |
| `PRODUCTS_CONFIG_PATH` | `config/products.toml` | Path to the IAP product credit tiers TOML. |
| `ADMIT_FLOOR_CREDITS` | `50` | Minimum credits required to admit an inference request (≈ €0.50). |
| `TOKEN_RATE_LIMIT_REQUESTS` | `20` | Max inference completions per token per window. |
| `TOKEN_RATE_LIMIT_WINDOW_SECONDS` | `60` | Rate limit window for per-token limiting. |

Runtime-tunable values (`UPSTREAM_API_KEY`, `UPSTREAM_API_URL`, `TOKEN_ENCRYPTION_KEY`, `APPLE_BUNDLE_ID`) are stored in Scaleway Secret Manager in production — update them there and restart the container. Model catalog and product tiers (`models.toml`, `products.toml`) are deploy-time config — update them in the repo and redeploy.

## Design principles

**Stateless and anonymous by design.** The relay is a bridge, not a backend. It holds no user data and no user identifiers. The shared auth key exists to exclude non-Eigin clients, not to identify who is asking. This constraint applies to future work too — agent sync and agent-to-agent connectivity should be designed to preserve anonymity, not work around it.

**The credit ledger stores purchase fingerprints, never user identity.** A wallet is keyed by a SHA-256 hash of an Apple transaction ID — it identifies a purchase, not a person. The user never creates an Eigin account. We know about purchases; we do not know about users.

**Zero content retention.** The inference proxy reads upstream usage metadata (token counts, model ID) from responses to compute cost. It never logs or stores prompt or response content. No content should appear in traces, logs, or debug output — do not add `tracing` calls that include request/response bodies.

**Debit after spend.** Inference requests are admitted if balance > admit floor. The true cost is settled after the stream completes, using the upstream usage block. A request may cause the balance to go slightly negative; the next request is then blocked by the floor check.

## API reference

`GET /docs` serves a Scalar API reference page. The OpenAPI spec (`api.yaml`, in the relay
source root) is embedded in the binary at compile time via `include_str!` — no runtime file
read required. Changing `api.yaml` requires a rebuild; the Terraform image hash includes the
file so a deploy picks up changes automatically.

## Key patterns

- **Shared state**: `AppState` is wrapped in `Arc` and passed to all handlers via Axum's `.with_state()`
- **Quota pool**: The monthly search quota is tracked in `Pool` and persisted via a `PoolBackend`. In production this is S3 with ETag-based optimistic locking; locally it can be a file or in-memory.
- **Auth**: All routes except `/health` require the `EIGIN_RELAY_KEY` header, enforced via Tower middleware
- **Tests**: Integration tests mock the upstream search API with `httpmock`; pool tests use `PoolConfig::LocalFile(tempdir)` directly — no env var mutation

## Deployment

Deployed to Scaleway Serverless Containers via Terraform. From the repo root:

```
just infra init              # First-time: terraform init (downloads providers)
just infra plan              # Preview staging changes
just infra plan production
just infra deploy            # Deploy to staging
just infra deploy production
```

`ENV` defaults to `staging`. The correct per-env relay key and Mojeek key are resolved automatically from `.env` via `scripts/tf-env.sh` — no manual TF_VAR edits required. See `infra/scaleway/` for the Terraform configuration.

### Custom domain (one-time setup)

The custom domain binding is not managed by Terraform because Scaleway's TLS provisioning requires the DNS record to be fully propagated before the binding is created — which can't be guaranteed in a single apply.

After the first deploy:

1. Add a CNAME record at your DNS provider pointing to the container's default URL (shown in `terraform output service_url`):
   - staging: `staging.relay.eigin.ai` → `<container-domain>`
   - production: `relay.eigin.ai` → `<container-domain>`
2. Wait for the record to propagate: `dig staging.relay.eigin.ai` should return the container domain.
3. In the Scaleway console, go to the container → **Endpoints** → **Add endpoint** and enter the custom hostname.

Subsequent `just infra deploy` runs do not touch the domain binding.
