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
| `POOL_FILE_PATH` | `/data/pool.json` | Where the quota pool is persisted |
| `PORT` | `8080` | Listen port |

## Design principles

**Stateless and anonymous by design.** The relay is a bridge, not a backend. It holds no user data and no user identifiers. The shared auth key exists to exclude non-Eigin clients, not to identify who is asking. This constraint applies to future work too — agent sync and agent-to-agent connectivity should be designed to preserve anonymity, not work around it.

## Key patterns

- **Shared state**: `AppState` is wrapped in `Arc` and passed to all handlers via Axum's `.with_state()`
- **Quota pool**: The monthly search quota is tracked in `Pool` and persisted as JSON to `POOL_FILE_PATH` — not a database
- **Auth**: All routes except `/health` require the `EIGIN_RELAY_KEY` header, enforced via Tower middleware
- **Tests**: Integration tests mock the upstream search API with `httpmock`

## Deployment

A `Dockerfile` is included. Run `make relay-build` to build, `make relay-test` to test.
