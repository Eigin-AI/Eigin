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
| Test Rust, browser bindings, and Apple bindings/packages (macOS) | `just test sdk` |
| Test the CLI | `just test cli` |
| Test browser packages and applications | `just test web` |
| Run the CLI | `just run cli init` |
| Run the browser test host | `just run web app` |

Build commands generate required artifacts. Generated bindings and binaries are ignored; generate Apple artifacts before opening the Swift package in Xcode.

## Bindings

- Swift uses UniFFI 0.31.0. Browser bindings use `uniffi-bindgen-react-native` / `@ubjs` 0.31.0-6 and `wasm2`. Upgrade these together when compatible releases are available.
- Apple uses a dynamic XCFramework alongside Firm’s static library. Xcode embeds and signs it for the application.
- Browser checks compile WASM and exercise supported operations in Chromium, Firefox, and WebKit. Compilation alone cannot detect every unsupported platform operation; see the [Rust target documentation](https://doc.rust-lang.org/rustc/platform-support/wasm32-unknown-unknown.html).
- Rust error declarations generate Swift and TypeScript error types and payload conversions. Adding an error requires no manual host model or mapping. Keep error types alongside their capabilities.

See the [migration record](../../docs/plans/145-sdk-migration.md) for implementation decisions and verification evidence, and the [SDK dependency inventory](../../LICENSES/eigin_sdk.md) for attribution.

## Test layers

| Layer | Location | Coverage |
|---|---|---|
| SDK behavior | `crates/eigin_sdk/src/` | Real operation outcomes and error conditions |
| Binding contracts | `tests/swift/Tests/BindingContractTests/`, `web/tests/contracts.ts` | Typed payloads, callbacks, pending work and wakeups |
| Package smoke tests | `apple/EiginSDK/Tests/`, `web/tests/host.spec.ts` | Production artifact loading and initialization |

`just test sdk` runs all three layers; Apple checks require macOS and Xcode and are skipped elsewhere.
Default `just test` includes these checks, with browser tests run through the web workspaces.

Focused commands, from the repository root:
- Swift contracts: `cargo run --manifest-path tools/Cargo.toml -- check-sdk-bindings apple`.
- Browser: `just generate sdk web`, then `npm test --workspace @eigin/sdk`.

### Add coverage

- Test real error conditions in Rust. Add host cases for new boundary shapes and important public contracts.
- Add a Swift XCTest method using `ContractTestCase.check`, and a browser function exposed through `contracts.ts`
  called directly from `contracts.spec.ts`. Assert generated variants and payloads.
- For controlled outcomes, add a helper under the `binding_tests` module. These separate exports use the
  `binding-tests` feature; production artifacts exclude them.
- For wakeups, start `PendingOperation.run`, await `wait_until_pending`, then call `succeed` or `fail`.
  Host test timeouts bound failures. Use one operation instance per case.
- Add browser runtime coverage when platform-sensitive operations arrive; compilation alone cannot detect unsupported I/O.

## Diagnostics

Hosts route SDK events through `EiginSDK.Diagnostics` (Swift) or
`setDiagnosticReceiver` (browser). Private values require explicit opt-in.
Callbacks are synchronous and may be concurrent on native hosts; return quickly
and avoid SDK calls from callbacks. iOS routes events to AppLogger's `sdk` category.
