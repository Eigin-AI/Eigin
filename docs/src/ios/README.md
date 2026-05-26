# iOS

Eigin's iOS app is built with Swift 6, SwiftUI, SwiftData, and targets iOS 26. It is the only Eigin client today.

## Worth knowing

**Domain-first layout.** The codebase is organised into vertical slices under `Sources/` - each domain owns its models, services, views, and tools. Dependency order runs `Core → Inference → Provider → Agent → Chat → Onboarding → App`.

**Dependency injection via Factory.** Services are registered as singletons in a [Factory](https://github.com/hmlongco/Factory) container and resolved at point of use with `@Injected` in views or `Container.shared` in services. Registrations live in `App/Container+Services.swift`. Test doubles are registered on the container in test setup and are called Fakes, not Mocks.

**Knowledge via Firm.** The knowledge graph is backed by [Firm](https://github.com/42futures/firm), a plain-text DSL for structured knowledge. Each entity is stored as a `.firm` source file, persisted as a `FirmSource` SwiftData model with an embedding vector for semantic search.

**Live call via CallKit.** The live call session uses the platform's CallKit framework to stay alive when the device is locked, showing native call UI on the lock screen. This is what makes the experience work like a phone call rather than a foreground-only feature.

**Local ML via Core ML.** On-device models run as Core ML models. We've evaluated alternatives including MLX, but on iOS, non-Core ML runtimes count against app memory in ways that make them impractical. Core ML keeps memory overhead within acceptable bounds.

**Localisation via a generated enum.** All user-facing strings live in `Localizable.xcstrings` and are accessed through the generated `Localized` enum. The app switches language at runtime via `Bundle.appLanguage` rather than being tied to the system locale. Run `just generate` after catalog changes to regenerate the enum.

## Build

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen). Don't edit the `.xcodeproj` directly: edit `project.yml` and regenerate.

```
just generate       # Regenerate the project
just build ios      # Build the iOS app
just test ios       # Run the iOS test suite
```
