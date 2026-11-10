# Eigin SDK

Portable Rust SDK for Eigin agents, with bindings and integration packages for supported platforms.

Start with the [SDK guide](../../docs/src/sdk/README.md) for an introduction and [getting started](../../docs/src/sdk/getting-started.md). See [Developing the SDK](../../docs/src/contributing/sdk.md) for binding and testing guidance.

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
| Test Rust, browser bindings, and Apple bindings/packages (macOS) | `just test sdk` |
| Test the CLI | `just test cli` |
| Test browser packages and applications | `just test web` |
| Run the CLI | `just run cli init` |
| Run the browser test host | `just run web app` |

Build commands generate required artifacts. Generated bindings and binaries are ignored; generate Apple artifacts before opening the Swift package in Xcode.
