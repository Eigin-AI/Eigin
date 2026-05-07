# Eigin for iOS
iOS 26, Swift 6, SwiftUI, SwiftData.

## Project structure

```
Sources/
  Core/        — persistence, tools infrastructure, audio, design tokens, shared utilities
  Inference/   — API clients, wire types, local model runner
  Provider/    — provider + MCP configuration
  Agent/       — agent config, knowledge, intents, skills, spaces, schedule, food, web
  Chat/        — chat + live call
  Onboarding/  — onboarding flow
  App/         — app entry point, DI container, settings, tool assembly
  Utilities/   — shared helpers
Tests/
  Fakes/       — test doubles
```

Top-level folders are **domain verticals**. Each domain owns its models, services, views, and tools in subfolders (e.g. `Provider/Models/`, `Provider/Services/`, `Provider/Views/`).

## Prerequisites

- Xcode (with `xcode-select -s /Applications/Xcode.app/Contents/Developer`)
- XcodeGen (`brew install xcodegen`)
- SwiftFormat (`brew install swiftformat`)

## Environments

Two build targets, each hardwired to a relay environment:

| Target / scheme | Relay | Bundle ID |
|---|---|---|
| `Eigin` | `relay.eigin.ai` (production) | `${BUNDLE_ID}` |
| `EiginDev` | `staging.relay.eigin.ai` (staging) | `${BUNDLE_ID}.dev` |

Both apps can be installed on the same device simultaneously. The relay URL and key come from `.env` via `_STAGING` / `_PRODUCTION` suffix labels (e.g. `EIGIN_RELAY_URL_STAGING`, `EIGIN_RELAY_KEY_PRODUCTION`). Build with `make ios-build` for production or `make ios-build SCHEME=EiginDev` for staging.

## Project generation

The Xcode project is generated from `project.yml` — never edit `.xcodeproj` directly. To add files, dependencies, or build settings, edit `project.yml` then regenerate:

```
make generate   # regenerate project
make ios-open   # regenerate and open in Xcode
```

## Development principles

- **Views stay thin**: Extract data transformation/validation/orchestration to utils and services. Views present data and handle interaction
- **Services own logic**: Each domain owns its services alongside its models and views. Services should read as operations, not type definitions
- **Dependency injection**: Protocol-based services registered in a [Factory](https://github.com/hmlongco/Factory) `Container` (`App/Container+Services.swift`). Views use `@Injected(\.service)`, service layer uses `Container.shared.<service>()`. Only ThemeManager stays on `@Environment`
- **Design tokens**: Use centralised `Typography` and `Spacing` enums from `Core/Design/`
- **Tool kits**: Each domain registers its tools via a `ToolKit` conformance. `App/ToolAssembly.swift` composes all kits

## Localization

All user-facing strings live in `Sources/Localizable.xcstrings` and are accessed via the generated `Localized` enum. See [`docs/src/ios/localization.md`](../../docs/src/ios/localization.md) for the full workflow.

## Code style

Formatting is enforced by SwiftFormat — config at `src/eigin_ios/.swiftformat`. Run `make format` from the repo root before committing.

## Testing

Framework is Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`). One test file per service: `{Service}Tests.swift`. Fakes live in `Tests/Fakes/`. A common pattern is `FakeURLProtocol` injected into `URLSession` to intercept network calls without hitting the real network.

Run with `make ios-test`.
