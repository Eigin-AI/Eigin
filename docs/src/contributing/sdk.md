# Developing the SDK

- [SDK README][readme]: setup and commands.
- [SDK guide](../sdk/README.md): host integration.

## Bindings

- Define shared behavior and errors in Rust.
- Regenerate bindings after API changes.
- Keep UniFFI and browser binding tools compatible.
- Generate Apple artifacts before opening Xcode.
- Embed and sign the XCFramework in the app.
- Test WASM in browsers. Compilation cannot catch every [platform limitation][wasm].

## Testing

`just test sdk` runs three layers:

| Layer | Checks |
| --- | --- |
| Rust | Behavior and errors |
| Bindings | Payloads, callbacks, and async work |
| Packages | Artifact loading and initialization |

Apple tests require macOS and Xcode. They are skipped elsewhere.
Browser tests run in Chromium, Firefox, and WebKit.

For focused checks, use these commands from the repository root.

**Swift contracts:**

```sh
cargo run --manifest-path tools/Cargo.toml -- check-sdk-bindings apple
```

**Browser:**

```sh
just generate sdk web
npm test --workspace @eigin/sdk
```

## Adding coverage

- Test behavior and errors in Rust.
- Add host tests for new binding contracts.
- Use `ContractTestCase.check` in Swift.
- Call browser cases in `contracts.ts` from `contracts.spec.ts`.
- Keep test-only exports in `binding_tests`, behind `binding-tests`.
- Test async success and failure. Use one operation per case and set timeouts.
- Test platform-sensitive operations in browsers.

## References

- [Dependency inventory][licenses]
- [Migration record][migration]

[readme]: https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_sdk/README.md
[wasm]: https://doc.rust-lang.org/rustc/platform-support/wasm32-unknown-unknown.html
[licenses]: https://code.eigin.ai/dev/eigin/-/blob/main/LICENSES/eigin_sdk.md
[migration]: https://code.eigin.ai/dev/eigin/-/blob/main/docs/plans/145-sdk-migration.md
