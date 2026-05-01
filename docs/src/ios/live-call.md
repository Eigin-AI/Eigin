# Live call on iOS

`LiveCallService` is a `@MainActor @Observable` class that owns the full turn loop. It runs through four phases:

```
idle → listening → processing → speaking → listening → …
```

**Listening** — a dedicated `DefaultDictationService` instance streams partial transcriptions. A silence detector watches for a configurable gap (fast / balanced / slow) with no new transcription; when it fires, it ends the listening phase and submits the turn.

**Processing** — `AgenticChatLoop` runs the inference turn with tool support. MCP servers are discovered per-turn. The completion result is handed to the speech service.

**Speaking** — `SpeechService` streams the response audio sentence by sentence. When playback finishes, the `onComplete` callback fires and the loop returns to listening.

## CallKit

`CallManager.shared` (CallKit) keeps the session alive in the background and shows native call UI on the lock screen. The call is started when the live call begins and ended when it stops. This is what makes the experience work like a phone call rather than a foreground-only feature.

## Persistence

`LiveCallService` doesn't write to SwiftData directly. The caller provides an `onPersist` callback that fires after each turn with the updated message array. SwiftData writes stay on the main actor in the view layer.

## Critical files

- `src/eigin_ios/Sources/Chat/LiveCall/Services/LiveCallService.swift` — orchestration
- `src/eigin_ios/Sources/Chat/LiveCall/Models/LiveCallContext.swift` — dependencies passed at start
- `src/eigin_ios/Sources/Chat/LiveCall/Views/LiveCallView.swift` — entry point and persistence callback
