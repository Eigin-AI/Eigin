# Eigin SDK dependencies

Direct dependencies of `src/eigin_sdk/`. Resolved transitive dependencies are recorded in its Cargo lockfile.

Consumers: Eigin iOS, the browser test host, and the Rust CLI. Each consumer owns its application dependencies.

| Dependency | Version | Scope | License |
|---|---|---|---|
| [futures](https://github.com/rust-lang/futures-rs) | 0.3.34 | test | MIT OR Apache-2.0 |
| [thiserror](https://github.com/dtolnay/thiserror) | 2.0.21 | runtime | MIT OR Apache-2.0 |
| [uniffi](https://github.com/mozilla/uniffi-rs) | 0.31.0 | runtime | MPL-2.0 |
| [uniffi-runtime-wasm](https://github.com/jhugman/uniffi-bindgen-react-native) | 0.31.0-6 | runtime | MPL-2.0 |
| [uniffi_core](https://github.com/mozilla/uniffi-rs) | 0.31.0 | runtime | MPL-2.0 |

## Browser package

| Dependency | Version | License |
|---|---|---|
| `@ubjs/core` | 0.31.0-6 | MPL-2.0 |
| `@ubjs/wasm` | 0.31.0-6 | MPL-2.0 |
| `uniffi-bindgen-react-native` (generator) | 0.31.0-6 | MPL-2.0 |

Upstream: https://github.com/jhugman/uniffi-bindgen-react-native.
Browser test/build tooling is listed in [web packages](web-packages.md).
[UniFFI source notices and MPL text](uniffi/README.md) are also displayed by consumers that ship the runtime.
