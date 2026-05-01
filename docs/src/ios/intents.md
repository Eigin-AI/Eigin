# Intents on iOS

`Intent` is a SwiftData `@Model` with a `content` string, a `status` (active / resolved / dismissed), a `reinforcedCount`, and timestamps. The decay logic lives entirely in a computed property:

```swift
var effectiveStrength: Double {
    let days = Date.now.timeIntervalSince(updatedAt) / 86400
    let halfLife = Double(min(
        IntentDecay.baseHalfLifeDays + IntentDecay.reinforcementBonusDays * reinforcedCount,
        IntentDecay.maxHalfLifeDays
    ))
    return exp(-days / halfLife)
}
```

No scheduled jobs, no background decay passes — strength is computed on read from `updatedAt` and the reinforcement count.

## The Sendable problem

`@Model` types aren't `Sendable`, so `Intent` can't cross actor boundaries directly. `IntentSnapshot` is a plain `Sendable` struct that copies the fields needed by callers. `IntentService` methods return `[IntentSnapshot]`, not `[Intent]`. This pattern — `@Model` for persistence, snapshot for passing around — repeats elsewhere in the codebase.

## Critical files

- `src/eigin_ios/Sources/Core/Persistence/SchemaVersions/SchemaV1/SchemaV1+Intent.swift` — `@Model` + `effectiveStrength`
- `src/eigin_ios/Sources/Agent/Intent/Models/IntentStatus.swift` — status enum + `IntentDecay` constants
- `src/eigin_ios/Sources/Agent/Intent/Services/IntentService.swift` — protocol, `IntentSnapshot`, `DefaultIntentService`
