# iOS

Eigin's iOS app is built with Swift 6, SwiftUI, SwiftData, and targets iOS 26. It's the only Eigin client today.

## Worth knowing

**Domain-first layout.** The codebase is organised into vertical slices under `Sources/`: each domain owns its models, services, views, and tools. Dependency order runs `Core → Inference → Provider → Agent → Chat → Onboarding → App`.

**Dependency injection via Factory.** Services are singletons in a [Factory](https://github.com/hmlongco/Factory) container, resolved with `@Injected` in views or `Container.shared` in services. Registrations live in `App/Container+Services.swift`. Test doubles are registered in test setup and called Fakes, not Mocks.

**Knowledge via Firm.** The knowledge graph is backed by [Firm](https://github.com/42futures/firm), a plain-text DSL for structured knowledge. Each entity is a `.firm` source file, persisted as a `FirmSource` SwiftData model with an embedding vector for semantic search.

**Live call via CallKit.** The live call session uses CallKit to stay alive when the device is locked, showing native call UI on the lock screen. This is what makes it feel like a phone call rather than a foreground-only feature.

**Local ML via LiteRT-LM.** On-device models run through Google's LiteRT-LM runtime on the GPU/Metal backend, using a quantization-aware-trained Gemma 4 E2B build. See [Local model](local-model.md). Apple's Foundation Models framework is wired in as a second local option.

**Localisation via a generated enum.** User-facing strings live in `Localizable.xcstrings`, accessed through the generated `Localized` enum. The app switches language at runtime via `Bundle.appLanguage` rather than the system locale. Run `just generate` after catalog changes.

## Build

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen). Don't edit the `.xcodeproj` directly: edit `project.yml` and regenerate.

```
just generate       # Regenerate the project
just build ios      # Build the iOS app
just test ios       # Run the iOS test suite
```

Releasing to TestFlight / the App Store is automated via Fastlane — see
[Releasing](releasing.md).
