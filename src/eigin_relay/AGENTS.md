# Eigin Relay
Rust, Axum 0.8, Tower, Tokio.

The relay provides connectivity services that can't be bundled into the app — primarily proxying search APIs (Staan) while managing a community pool of shared API quota. It also enforces per-IP rate limiting and authenticates requests from Eigin clients.

Going forward, this is the intended home for agent synchronisation and agent-to-agent discovery. Neither is implemented yet.

## Project structure

```
src/
  main.rs         — server setup, env config, router
  lib.rs          — public API
  auth/           — authentication and request identity
    key.rs        — x-eigin-key middleware (accepts primary + optional secondary key)
    bearer.rs     — Bearer-token extractor (credit token → wallet lookup)
  rate_limit.rs   — sliding window rate limiter, generic over key type (IpAddr or Uuid)
  state.rs        — shared AppState (Arc)
  health.rs       — health check handler
  error.rs        — AppError type (OpenAI-compatible JSON error body)
  search/         — search proxy (client, handler)
  quota/          — shared rolling-window flow cap (search pool + sandbox budget)
    mod.rs        — Quota trait + QuotaError
    bucket.rs     — day-bucket window math
    memory.rs     — InMemoryQuota (tests / dev)
    postgres.rs   — PostgresQuota (per-key daily buckets, advisory-locked upsert)
  credits/        — credit system (tokens, ledger, Apple verification, HTTP handlers)
    mod.rs        — public exports
    token.rs      — token generation (eict_ prefix), SHA-256 hashing, AEAD at-rest encryption
    ledger.rs     — CreditLedger trait + types (Wallet, WalletOrigin, WalletStatus)
    memory.rs     — InMemoryLedger (tests / dev)
    postgres.rs   — PostgresLedger + connect_and_migrate (sqlx, shared pool)
    apple/        — AppleVerifier trait, AppStoreVerifier + MultiEnvironmentVerifier, webhook
    redeem.rs     — POST /credits/redeem (purchase + idempotent restore, sandbox budget gate)
    balance.rs    — GET /credits/balance
    webhook.rs    — POST /webhooks/apple/appstore (App Store Server Notifications V2)
  inference/      — OpenAI-compatible inference proxy with credit metering
    mod.rs        — public exports
    catalog.rs    — models.toml + products.toml loading + GET /v1/models
    rates.rs      — usage → millicredits cost computation
    usage.rs      — SSE/JSON usage-block extraction (never touches content)
    upstream.rs   — UpstreamClient trait + reqwest impl
    handler.rs    — POST /v1/chat/completions (reserve, stream, settle)
  assets/         — self-hosted model-asset mirror (manifests + presigned URLs)
    mod.rs        — public exports
    catalog.rs    — assets.toml loading (pinned versions + manifest shas)
    store.rs      — AssetStore trait, Scaleway S3 impl, InMemory fake, Inert placeholder
    cache.rs      — sha-verified lazy manifest cache
    handler.rs    — GET /v1/assets, GET /v1/assets/{id}
migrations/
  0001_create_wallets.sql
  0002_create_processed_notifications.sql
  0003_create_quota_buckets.sql
config/
  models.toml     — curated model catalog + credit rates (TODO: pin to provider)
  products.toml   — IAP product credit tiers (TODO: pin to App Store products before launch)
  assets.toml     — asset-mirror pointers: id → pinned version + manifest sha
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
| `STAAN_API_KEY` | required | Upstream search API key |
| `EIGIN_RELAY_PRIMARY_KEY` | required | Shared auth key expected from Eigin clients (the key the app bakes in) |
| `EIGIN_RELAY_SECONDARY_KEY` | — | Optional second accepted key. Holds the previous key during a rotation so already-shipped app builds keep working; clear it once they retire. |
| `SEARCH_API_URL` | `https://api.staan.ai/v2` | Upstream search base URL |
| `RATE_LIMIT_REQUESTS` | `10` | Max requests per window per IP |
| `RATE_LIMIT_WINDOW_SECONDS` | `60` | Rate limit window duration |
| `MONTHLY_POOL_SIZE` | `5000` | Max searches the community pool allows per rolling window |
| `SEARCH_POOL_WINDOW_DAYS` | `30` | Trailing window over which the search pool is measured |
| `PORT` | `8080` | Listen port |

The search pool is backed by the shared rolling-window quota in Postgres (see Credits and inference). When `DATABASE_URL` is unset, the quota runs in-memory (resets on restart, dev only).

### Credits and inference

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | — | Postgres connection string. If unset, uses `InMemoryLedger` (dev only, logs a warning). |
| `TOKEN_ENCRYPTION_KEY_PRIMARY` | — | 32-byte base64url AEAD key for encrypting credit tokens at rest. Generate with `openssl rand -base64 32`. Terraform-generated in production. |
| `TOKEN_ENCRYPTION_KEY_SECONDARY` | — | Optional previous token key, set only during a rotation so tokens minted under the old key stay restorable. See the [token key rotation runbook](../../docs/src/runbooks/token-key-rotation.md). |
| `UPSTREAM_API_URL` | — | Base URL of the upstream inference provider. If unset, inference routes return 503. |
| `UPSTREAM_API_KEY` | — | API key for the upstream inference provider. |
| `APPLE_BUNDLE_ID` | — | Comma-separated set of accepted app bundle IDs, e.g. `ai.eigin.finch`. List several to serve multiple apps at once, e.g. `com.42futures.carrel,ai.eigin.finch` during a bundle-ID migration. Each bundle ID is verified across every `APPLE_ENVIRONMENTS` entry. |
| `APPLE_ENVIRONMENTS` | `Sandbox` | Comma-separated environments to accept, e.g. `Sandbox` (staging) or `Production,Sandbox` (production accepts TestFlight/App-Review sandbox purchases). Terraform models this as a `list(string)` and joins it for this var. |
| `APPLE_APP_APPLE_ID` | — | Numeric App Store app ID. Required in Production. |
| `SANDBOX_MONTHLY_CREDIT_BUDGET` | `25000` | Max credits issued to Sandbox purchases per rolling window. Bounds free-credit abuse cost. |
| `SANDBOX_BUDGET_WINDOW_DAYS` | `30` | Trailing window over which the sandbox issuance budget is measured. |
| `WEBHOOK_RATE_LIMIT_REQUESTS` | `20` | Max Apple webhook requests per window per IP. Sized well above Apple's retry cadence (hours apart), just to bound flood cost on this unauthenticated route. |
| `WEBHOOK_RATE_LIMIT_WINDOW_SECONDS` | `60` | Rate limit window for the Apple webhook. |
| `MODELS_CONFIG_PATH` | `config/models.toml` | Path to the model catalog TOML. |
| `PRODUCTS_CONFIG_PATH` | `config/products.toml` | Path to the IAP product credit tiers TOML. |
| `TOKEN_RATE_LIMIT_REQUESTS` | `20` | Max inference completions per token per window. |
| `TOKEN_RATE_LIMIT_WINDOW_SECONDS` | `60` | Rate limit window for per-token limiting. |

Runtime-tunable values (`UPSTREAM_API_KEY`, `UPSTREAM_API_URL`, `APPLE_BUNDLE_ID`) are stored in Scaleway Secret Manager in production — update them there and restart the container. Model catalog and product tiers (`models.toml`, `products.toml`) are deploy-time config — update them in the repo and redeploy.

`TOKEN_ENCRYPTION_KEY_PRIMARY` and the relay/grant keys are Terraform-generated (owned in state), not hand-edited secrets. Rotating them is a deliberate procedure — see the [runbooks](../../docs/src/runbooks/README.md), in particular [token key rotation](../../docs/src/runbooks/token-key-rotation.md).

### Model assets

| Variable | Default | Description |
|---|---|---|
| `ASSETS_CONFIG_PATH` | `config/assets.toml` | Path to the asset pointer TOML. |
| `ASSETS_BUCKET` | — | Object-storage bucket for the asset mirror. All five S3 vars must be set together; with none set the module is inert (empty catalog 404s) and configured entries 503 at serve time. |
| `S3_ENDPOINT` | — | S3 endpoint, e.g. `https://s3.fr-par.scw.cloud`. |
| `S3_REGION` | — | Bucket region, e.g. `fr-par`. |
| `S3_ACCESS_KEY` | — | Read-only credential for the bucket (Terraform-generated in production). |
| `S3_SECRET_KEY` | — | Secret half of the read credential. |
| `PRESIGN_EXPIRY_SECONDS` | `86400` | How long presigned download URLs in `GET /v1/assets/{id}` stay valid. |

Asset swaps are deploy-time config: `eigin-tools assets upload` mints a version, then an
MR bumps `assets.toml` (the image hash covers it, so the deploy is automatic). See the
[model-mirror runbook](../../docs/src/runbooks/model-mirror.md).

## Design principles

**Stateless and anonymous by design.** The relay is a bridge, not a backend. It holds no user data and no user identifiers. The shared auth key exists to exclude non-Eigin clients, not to identify who is asking. This constraint applies to future work too — agent sync and agent-to-agent connectivity should be designed to preserve anonymity, not work around it.

**The credit ledger stores purchase fingerprints, never user identity.** A wallet is keyed by a SHA-256 hash of an Apple transaction ID — it identifies a purchase, not a person. The user never creates an Eigin account. We know about purchases; we do not know about users.

**Zero content retention.** The inference proxy reads upstream usage metadata (token counts, model ID) from responses to compute cost. It never logs or stores prompt or response content. No content should appear in traces, logs, or debug output — do not add `tracing` calls that include request/response bodies.

**Reserve then settle.** Inference requests reserve the estimated cost against the balance before forwarding — a conditional atomic debit that refuses if the balance can't cover it, so concurrent requests can't each draw the same balance and overspend. After the stream completes the reservation is reconciled to actual usage: the signed delta `actual − reserved` is applied (charging the overrun, refunding the surplus). A single request may push the balance slightly negative when actual usage exceeds the estimate; the next request is then refused, since the reservation requires a non-negative balance. There is no static admit floor — users can spend down to their last credit.

## API reference

`GET /docs` serves a Scalar API reference page. The OpenAPI spec (`api.yaml`, in the relay
source root) is embedded in the binary at compile time via `include_str!` — no runtime file
read required. Changing `api.yaml` requires a rebuild; the Terraform image hash includes the
file so a deploy picks up changes automatically.

## Key patterns

- **Shared state**: `AppState` is wrapped in `Arc` and passed to all handlers via Axum's `.with_state()`
- **Quota pool**: The monthly search quota is tracked in `Pool` and persisted via a `PoolBackend`. In production this is S3 with ETag-based optimistic locking; locally it can be a file or in-memory.
- **Auth**: All routes except `/health` require a valid `x-eigin-key` header (matching the configured primary or secondary key), enforced via Tower middleware
- **Tests**: Integration tests mock the upstream search API with `httpmock`; quota tests use `InMemoryQuota` (Postgres quota tests are `#[ignore]`, gated on `DATABASE_URL`) — no env var mutation

## Deployment

Deployed to Scaleway Serverless Containers via Terraform. From the repo root:

```
just infra init              # First-time: terraform init (downloads providers)
just infra plan              # Preview staging changes
just infra plan production
just infra deploy            # Deploy to staging
just infra deploy production
```

`ENV` defaults to `staging`. `eigin-tools config export tf-vars <env>` resolves the per-env relay key and Staan key from `.env`. See `infra/scaleway/` for the Terraform configuration.

### Custom domain (one-time setup)

The custom domain binding is not managed by Terraform because Scaleway's TLS provisioning requires the DNS record to be fully propagated before the binding is created — which can't be guaranteed in a single apply.

After the first deploy:

1. Add a CNAME record at your DNS provider pointing to the container's default URL (shown in `terraform output service_url`):
   - staging: `staging.relay.eigin.ai` → `<container-domain>`
   - production: `relay.eigin.ai` → `<container-domain>`
2. Wait for the record to propagate: `dig staging.relay.eigin.ai` should return the container domain.
3. In the Scaleway console, go to the container → **Endpoints** → **Add endpoint** and enter the custom hostname.

Subsequent `just infra deploy` runs do not touch the domain binding.
