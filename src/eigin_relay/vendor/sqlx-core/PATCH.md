# Temporary SQLx pool-return deadline — issue #348

## Provenance

Source: published `sqlx-core` 0.8.6 crate from crates.io.
Archive SHA-256:
`ee6798b1838b6a0f69c007c133b8df5866302197e404e8b6ee8ed3e3a5e68dc6`.

The Cargo manifests, `src/`, and MIT/Apache-2.0 licenses are copied unchanged,
except for the modification below. Cargo registry bookkeeping is omitted.

References:

- https://github.com/transact-rs/sqlx/issues/4349
- https://github.com/transact-rs/sqlx/pull/4407
- https://github.com/transact-rs/sqlx/issues/4449

This is a local implementation of a bounded return, not a copy of an upstream
PR diff. The production incident's exact trigger remains unconfirmed.

## Local modification

Only `src/pool/connection.rs` differs from the published source:

- Add a five-second `RETURN_TO_POOL_TIMEOUT`.
- Bound the entire `floating.return_to_pool()` future, including the release
  callback, ping, and close paths.
- On expiry, log a fixed warning and treat the return as unsuccessful.
  Dropping the future drops the connection and its `DecrementSizeGuard`,
  releasing the slot. Existing minimum-connection maintenance still runs.

Five seconds matches SQLx's existing close-on-drop deadline. Healthy returns
are unchanged. Release callbacks and cleanup of cancelled queries now have
this deadline; slow cleanup discards the connection instead of reusing it.
This is not a query execution timeout and does not resolve whether a cancelled
write committed on the server.

The relay's max connections and acquisition timeout remain unchanged.
The timeout warning uses SQLx's existing tracing target; select
`sqlx_core::pool::connection=warn` in RUST_LOG to see it. No SQL or parameters
are included in the new warning. Other existing SQLx warnings can include
backend error messages; do not enable query logging in production.

## Verification

See `tests/pool_recovery.rs` and `tests/pool-recovery.md`.
Tests cover silent established sockets with healthy fresh connectivity,
a stalled release callback, minimum-connection replenishment, cancelled
queries, normal connection reuse, and dropped transaction rollback.

The transport fault test covers the return ping over plain TCP and rustls TLS.
It does not separately force a stalled TLS close or test PgBouncer.
The deadline surrounds those close paths too, but they lack direct fault coverage.

## Removal

When an upstream release includes a bounded entire return operation:

1. Remove `[patch.crates-io]` from the relay manifest.
2. Upgrade SQLx and regenerate the lockfile.
3. Run the recovery checks and full relay tests against that release.
4. Delete this directory and update `LICENSES/rust-crates.md`.

Do not remove the regression checks with the override.
