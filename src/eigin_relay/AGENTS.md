# Eigin Relay
Rust, Axum 0.8, Tower, Tokio.

The relay provides connectivity services that can't be bundled into the app — primarily proxying search APIs (Mojeek) while managing a community pool of shared API quota. It also enforces per-IP rate limiting and authenticates requests from Eigin clients.

Going forward, this is the intended home for agent synchronisation and agent-to-agent discovery. Neither is implemented yet.

## Project structure

```
src/
  main.rs         — server setup, env config, router
  lib.rs          — public API
  auth.rs         — EIGIN_RELAY_KEY middleware
  rate_limit.rs   — per-IP rate limiter
  state.rs        — shared AppState (Arc)
  health.rs       — health check handler
  error.rs        — AppError type
  search/         — search proxy (client, handler, pool, connection pool)
    pool/
      backend.rs  — PoolBackend trait, PoolState, BackendError
      file.rs     — local file backend (dev / single-instance)
      s3.rs       — S3-compatible backend with SigV4 signing + ETag optimistic locking
      state.rs    — Pool, PoolConfig, PoolConfig::from_env()
tests/
  integration.rs  — integration tests using httpmock
```

## Prerequisites

- Rust and Cargo via [rustup](https://rustup.rs)

## Configuration

All configuration is via environment variables:

| Variable | Default | Description |
|---|---|---|
| `MOJEEK_API_KEY` | required | Upstream search API key |
| `EIGIN_RELAY_KEY` | required | Auth key expected from Eigin clients |
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

## Design principles

**Stateless and anonymous by design.** The relay is a bridge, not a backend. It holds no user data and no user identifiers. The shared auth key exists to exclude non-Eigin clients, not to identify who is asking. This constraint applies to future work too — agent sync and agent-to-agent connectivity should be designed to preserve anonymity, not work around it.

## Key patterns

- **Shared state**: `AppState` is wrapped in `Arc` and passed to all handlers via Axum's `.with_state()`
- **Quota pool**: The monthly search quota is tracked in `Pool` and persisted via a `PoolBackend`. In production this is S3 with ETag-based optimistic locking; locally it can be a file or in-memory.
- **Auth**: All routes except `/health` require the `EIGIN_RELAY_KEY` header, enforced via Tower middleware
- **Tests**: Integration tests mock the upstream search API with `httpmock`; pool tests use `PoolConfig::LocalFile(tempdir)` directly — no env var mutation

## Deployment

Deployed to Scaleway Serverless Containers via Terraform. From the repo root:

```
make infra-init              # First-time: terraform init (downloads providers)
make infra-plan              # Preview staging changes
make infra-plan ENV=production
make infra-deploy            # Deploy to staging
make infra-deploy ENV=production
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

Subsequent `make infra-deploy` runs do not touch the domain binding.
