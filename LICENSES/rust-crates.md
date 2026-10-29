# Rust Crate Licenses

| Crate | Repository | Version | License |
|-------|-----------|---------|---------|
| axum | https://github.com/tokio-rs/axum | 0.8 | MIT |
| tokio | https://github.com/tokio-rs/tokio | 1 | MIT |
| reqwest | https://github.com/seanmonstar/reqwest | 0.13 | MIT OR Apache-2.0 |
| serde | https://github.com/serde-rs/serde | 1 | MIT OR Apache-2.0 |
| serde_json | https://github.com/serde-rs/json | 1 | MIT OR Apache-2.0 |
| time | https://github.com/time-rs/time | 0.3 | MIT OR Apache-2.0 |
| tower | https://github.com/tower-rs/tower | 0.5 | MIT |
| tower-http | https://github.com/tower-rs/tower-http | 0.6 | MIT |
| tracing | https://github.com/tokio-rs/tracing | 0.1 | MIT OR Apache-2.0 |
| tracing-subscriber | https://github.com/tokio-rs/tracing | 0.3 | MIT OR Apache-2.0 |
| urlencoding | https://github.com/kornelski/rust_urlencoding | 2 | MIT |
| async-trait | https://github.com/dtolnay/async-trait | 0.1 | MIT OR Apache-2.0 |
| futures | https://github.com/rust-lang/futures-rs | 0.3 | MIT OR Apache-2.0 |
| bytes | https://github.com/tokio-rs/bytes | 1 | MIT |
| http | https://github.com/hyperium/http | 1 | MIT OR Apache-2.0 |
| minio | https://github.com/minio/minio-rs | 0.4 | Apache-2.0 |

## Vendored SQLx core

The relay includes `sqlx-core` 0.8.6 (MIT OR Apache-2.0) from
https://github.com/launchbadge/sqlx, with a local pool-return timeout patch.
Source, full license texts, provenance, and modification details are in
[`src/eigin_relay/vendor/sqlx-core`](../src/eigin_relay/vendor/sqlx-core/PATCH.md).

## Notes

- License types listed are as of the date this file was last updated (2026-05-07).
- Verify against each repository when upgrading to a new version.
- All crates use permissive licenses suitable for commercial use.