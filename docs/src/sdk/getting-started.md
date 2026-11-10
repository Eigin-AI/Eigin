# Getting started

Follow the [setup instructions](https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_sdk/README.md#setup), then choose your host interface:

| Host | Package | Preparation |
| --- | --- | --- |
| Rust | `src/eigin_sdk/crates/eigin_sdk` | Add a Cargo path dependency |
| Swift | `src/eigin_sdk/apple/EiginSDK` | `just generate sdk apple`, then add the local Swift package |
| Browser | `@eigin/sdk` | `just generate sdk web`, then import from the npm workspace |

## Initialize

Call initialization during application startup and handle errors in your host. In Swift:

```swift
import EiginSDK

func startSDK() async throws {
    try await EiginSDK.initialize()
}
```

In Rust, call `eigin_sdk::initialize().await?`. In the browser, import and await `initialize()` from `@eigin/sdk`.

## Connect diagnostics

Register a receiver before SDK operations to send events to your application's logs. For example, in a browser:

```typescript
import { initialize, setDiagnosticReceiver, DiagnosticLevel } from "@eigin/sdk";

await setDiagnosticReceiver(
  { receive(event) { console.debug(event.component, event.message); } },
  { minimumLevel: DiagnosticLevel.Debug, includePrivate: false },
);
await initialize();
```

In Swift, use `EiginSDK.Diagnostics.setReceiver`; in Rust, use `set_diagnostic_receiver`.

Private field values are withheld unless you opt in. Keep callbacks short, never throw, and avoid SDK calls; native callbacks may arrive concurrently.
