# Eigin SDK

Portable Rust SDK for Eigin agents, with bindings and integration packages for supported platforms.

| Interface | Package | Consumers |
|---|---|---|
| Rust | `crates/eigin_sdk` | Rust applications, including the Eigin CLI |
| Apple | `apple/EiginSDK` | Swift applications, including Eigin iOS |
| Browser | `web` (`@eigin/sdk`) | Browser applications, including the Eigin web test host |

## Setup

Install Rustup, Node.js 22.17+ with npm 10+, and `just`.
Apple builds also require macOS and Xcode 26; see the [iOS prerequisites](../eigin_ios/AGENTS.md).

```sh
rustup toolchain install 1.99.1 --profile minimal --component rustfmt --component clippy
rustup target add --toolchain 1.99.1 wasm32-unknown-unknown
```

Run commands from the repository root. Web generation restores missing npm tooling automatically.
For browser tests, install engines once with `npx playwright install chromium firefox webkit` after generation.

## Commands

| Task | Command |
|---|---|
| Generate browser bindings and WASM | `just generate sdk web` |
| Generate Swift bindings and Apple XCFramework | `just generate sdk apple` |
| Build Rust SDK for native and WASM | `just build sdk` |
| Build all browser packages and applications | `just build web` |
| Check native SDK and WASM compilation | `just test sdk` |
| Test the CLI | `just test cli` |
| Test browser packages and applications | `just test web` |
| Test Apple package and error bindings | `just test-sdk-apple` |
| Run the CLI | `just run cli init` |
| Run the browser test host | `just run web app` |

Build commands generate required artifacts. Generated bindings and binaries are ignored; generate Apple artifacts before opening the Swift package in Xcode.

## Bindings

- Swift uses UniFFI 0.31.0. Browser bindings use `uniffi-bindgen-react-native` / `@ubjs` 0.31.0-6 and `wasm2`. Upgrade these together when compatible releases are available.
- Apple uses a dynamic XCFramework alongside Firm’s static library. Xcode embeds and signs it for the application.
- Browser checks compile WASM and exercise supported operations in Chromium, Firefox, and WebKit. Compilation alone cannot detect every unsupported platform operation; see the [Rust target documentation](https://doc.rust-lang.org/rustc/platform-support/wasm32-unknown-unknown.html).
- Browser fixture tests and Apple fixture tests run independently. Package tests cover bindings; application smoke tests cover packaging, startup, and visible status.

See the [migration record](../../docs/plans/145-sdk-migration.md) for implementation decisions and verification evidence, and the [SDK dependency inventory](../../LICENSES/eigin_sdk.md) for attribution.
