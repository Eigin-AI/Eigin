# Services and dependency injection

All business logic lives in services. Each service follows a two-part pattern:

1. **Protocol** — defines the interface (`KnowledgeService`, `IntentService`, etc.)
2. **`Default*` implementation** — the real implementation, backed by SwiftData or system APIs

## Factory container

Services are registered as singletons in a [Factory](https://github.com/hmlongco/Factory) `Container` extension (`Container+Services.swift`) and resolved at point of use with `@Injected` (views) or `Container.shared.<service>()` (service layer).

```swift
// Register (Container+Services.swift)
extension Container {
    var fooService: Factory<any FooService> {
        self { DefaultFooService() }.singleton
    }
}

// Consume in a view
@Injected(\.fooService) private var fooService

// Consume in a service or pipeline
let foo = Container.shared.fooService()
```

For `@MainActor`-isolated services (e.g. audio services), annotate the factory property and closure:

```swift
@MainActor var speechService: Factory<any SpeechService> {
    self { @MainActor in DefaultSpeechService(...) }.singleton
}
```

## Adding a new service

1. Define the protocol in `<Domain>/Services/` (e.g. `Agent/Knowledge/Services/`)
2. Implement `Default<Service>` in the same folder
3. Register in `App/Container+Services.swift`
4. Consume via `@Injected` or `Container.shared`

That's it — no need to thread the service through EiginApp, views, view models, or pipelines.

## Testing

Register fakes on the container in test setup:

```swift
Container.shared.reset()
Container.shared.fooService.register { FakeFooService() }
```

Test doubles are called **Fakes** (not Mocks) and live in `Tests/Fakes/`.

## What stays on @Environment

- `ThemeManager` — SwiftUI-reactive, drives `\.colors`
- System-provided values: `\.locale`, `\.scenePhase`, `\.dismiss`, `\.modelContext`

## Critical files

- `src/eigin_ios/Sources/App/Container+Services.swift` — all service registrations
- `src/eigin_ios/Sources/App/EiginApp.swift` — app entry point (only ThemeManager and locale injected)
