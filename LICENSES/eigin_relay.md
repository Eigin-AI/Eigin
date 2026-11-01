# Eigin relay dependencies

Direct dependencies of `src/eigin_relay/`. Resolved transitive dependencies are recorded in its Cargo lockfile.

| Dependency | Version | Scope | License |
|---|---|---|---|
| [app-store-server-library](https://github.com/namecare/app-store-server-library-rust) | 4.3.0 | runtime | MIT |
| [async-trait](https://github.com/dtolnay/async-trait) | 0.1.92 | runtime | MIT OR Apache-2.0 |
| [axum](https://github.com/tokio-rs/axum) | 0.8.9 | runtime | MIT |
| [base64](https://github.com/marshallpierce/rust-base64) | 0.22.1 | runtime | MIT OR Apache-2.0 |
| [bytes](https://github.com/tokio-rs/bytes) | 1.12.1 | runtime | MIT |
| [chacha20poly1305](https://github.com/RustCrypto/AEADs/tree/master/chacha20poly1305) | 0.10.1 | runtime | Apache-2.0 OR MIT |
| [clap](https://github.com/clap-rs/clap) | 4.6.6 | runtime | MIT OR Apache-2.0 |
| [ed25519-dalek](https://github.com/dalek-cryptography/curve25519-dalek/tree/main/ed25519-dalek) | 2.2.0 | test | BSD-3-Clause |
| [futures](https://github.com/rust-lang/futures-rs) | 0.3.34 | runtime | MIT OR Apache-2.0 |
| [futures-util](https://github.com/rust-lang/futures-rs) | 0.3.34 | test | MIT OR Apache-2.0 |
| [hex](https://github.com/KokaKiwi/rust-hex) | 0.4.3 | runtime | MIT OR Apache-2.0 |
| [http](https://github.com/hyperium/http) | 1.5.0 | runtime | MIT OR Apache-2.0 |
| [http-body](https://github.com/hyperium/http-body) | 0.4.6 | test | MIT |
| [httpmock](https://github.com/alexliesenfeld/httpmock) | 0.7.0 | test | MIT |
| [jsonwebtoken](https://github.com/Keats/jsonwebtoken) | 9.3.1 | runtime | MIT |
| [object_store](https://github.com/apache/arrow-rs-object-store) | 0.14.1 | runtime | MIT/Apache-2.0 |
| [rand](https://github.com/rust-random/rand) | 0.8.7 | runtime | MIT OR Apache-2.0 |
| [reqwest](https://github.com/seanmonstar/reqwest) | 0.13.4 | runtime | MIT OR Apache-2.0 |
| [serde](https://github.com/serde-rs/serde) | 1.0.229 | runtime | MIT OR Apache-2.0 |
| [serde_json](https://github.com/serde-rs/json) | 1.0.151 | runtime | MIT OR Apache-2.0 |
| [sha2](https://github.com/RustCrypto/hashes) | 0.10.9 | runtime | MIT OR Apache-2.0 |
| [sqlx](https://github.com/launchbadge/sqlx) | 0.8.6 | runtime | MIT OR Apache-2.0 |
| [tempfile](https://github.com/Stebalien/tempfile) | 3.27.0 | test | MIT OR Apache-2.0 |
| [thiserror](https://github.com/dtolnay/thiserror) | 1.0.69 | runtime | MIT OR Apache-2.0 |
| [time](https://github.com/time-rs/time) | 0.3.55 | runtime | MIT OR Apache-2.0 |
| [tokio](https://github.com/tokio-rs/tokio) | 1.53.1 | runtime | MIT |
| [tokio-stream](https://github.com/tokio-rs/tokio) | 0.1.19 | runtime | MIT |
| [toml](https://github.com/toml-rs/toml) | 0.8.23 | runtime | MIT OR Apache-2.0 |
| [tower](https://github.com/tower-rs/tower) | 0.5.3 | runtime | MIT |
| [tower-http](https://github.com/tower-rs/tower-http) | 0.6.11 | runtime | MIT |
| [tracing](https://github.com/tokio-rs/tracing) | 0.1.44 | runtime | MIT |
| [tracing-subscriber](https://github.com/tokio-rs/tracing) | 0.3.23 | runtime | MIT |
| [url](https://github.com/servo/rust-url) | 2.5.8 | runtime | MIT OR Apache-2.0 |
| [urlencoding](https://github.com/kornelski/rust_urlencoding) | 2.1.3 | runtime | MIT |
| [uuid](https://github.com/uuid-rs/uuid) | 1.24.1 | runtime | Apache-2.0 OR MIT |

## Vendored SQLx core

`sqlx-core` 0.8.6 (MIT OR Apache-2.0) has a local pool-return timeout patch.
[Provenance, modifications, and full license texts](../src/eigin_relay/vendor/sqlx-core/PATCH.md) remain with the source.

## Legacy attribution

Minio 0.4 (Apache-2.0), https://github.com/minio/minio-rs, is retained from the earlier relay inventory.
