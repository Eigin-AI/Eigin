# iOS architecture

Eigin's iOS app is a Swift 6 / SwiftUI / SwiftData app targeting iOS 26.0. It's the only Eigin client today.

For what Eigin is at the system level, see [System context](../system-context.md). This page is about how the iOS app realises that.

## Source layout

The codebase follows a **domain-first** layout. Top-level folders under `Sources/` are vertical slices that own their models, services, views, and tools. Dependency order: `Core → Inference → Provider → Agent → Chat → Onboarding → App`.

```
src/eigin_ios/
├── project.yml                # XcodeGen project spec (source of truth)
├── Package.swift              # SPM package for editor LSP only — not used to build
├── Sources/
│   ├── Core/                  # Persistence, tools infrastructure, audio, design, utilities
│   │   ├── Audio/             # Speech, dictation, voice engines
│   │   ├── Design/            # Typography, spacing, themes
│   │   ├── Foundation/        # Base protocols and extensions
│   │   ├── Persistence/       # SwiftData schema versions
│   │   ├── Tools/             # Tool protocol, ToolRegistry, ToolKit, system tools
│   │   └── Utilities/         # Shared helpers
│   ├── Inference/             # API wire types and chat clients
│   │   ├── API/               # Anthropic + OpenAI-compatible wire types
│   │   └── Clients/           # ChatClient, LocalChatClient
│   ├── Provider/              # Provider + MCP configuration
│   │   ├── MCP/               # MCP server models, services, views, tools
│   │   ├── Models/ Services/ Views/
│   ├── Agent/                 # Agent configuration and sub-domains
│   │   ├── Knowledge/         # Knowledge graph (models, services, tools, views)
│   │   ├── Intent/            # Intent lifecycle
│   │   ├── Skill/             # Skill definitions and activation
│   │   ├── Space/             # Space management
│   │   ├── Schedule/          # Calendar + reminders
│   │   ├── Food/              # Food logging
│   │   ├── Web/               # Web search + fetch
│   │   ├── Models/ Services/ Views/ Tools/  # Agent-level concerns
│   ├── Chat/                  # Chat and live call
│   │   ├── LiveCall/          # Live call orchestration (models, services, views)
│   │   ├── Services/          # Chat services, gatekeeper, message pipeline
│   │   ├── Views/             # Chat UI (conversation, list)
│   │   └── Tools/             # Chat tools (ListChats, GetChatTranscript)
│   ├── Onboarding/            # Onboarding flow (models, services, views)
│   ├── App/                   # Composition root
│   │   ├── EiginApp.swift     # App entry point, ModelContainer, environment injection
│   │   ├── ContentView.swift  # Tab root
│   │   ├── Container+Services.swift  # Factory DI registrations
│   │   ├── ToolAssembly.swift # Composes all domain ToolKits
│   │   ├── Settings/          # Settings views
│   │   └── Debug/             # Debug UI
│   ├── Utilities/             # Thin shared helpers (not domain-specific)
│   └── Resources/             # Asset catalogs, localizations
└── Tests/
    ├── Fakes/                 # Test doubles (called Fakes, not Mocks)
    └── …
```

Each domain owns its models, services, views, and tools together. Tools are registered via `ToolKit` conformances — each domain defines a kit, and `App/ToolAssembly.swift` composes them.

## Navigation

The app has three tabs:

1. **Chats** — conversation list and active chat
2. **Agent** — agent configuration
3. **Settings** — appearance, language, providers, MCPs

This is intentionally small. You're either tinkering or thinking, not both.

## Persistence

Persistent data uses SwiftData. The `ModelContainer` is initialised at app startup with all `@Model` types: `Provider`, `Agent`, `Chat`, `Message`, `FirmSource` (knowledge entries), `Space`, `Intent`, permission grants, and so on. All on the user's device.

## Language

Each agent operates in a configured language. Language affects:

- **Dictation locale** — the speech recogniser is reconfigured for the active language
- **TTS voice selection** — the speech service prefers a voice matching the active language
- **String catalogs** — SwiftUI resolves localised strings based on the app language setting

The current supported languages are English and Danish (a canary for full localisation). The strategy is to get one majority and one minority language working well before expansion.

See [Localization](./localization.md) for how to add and use localised strings.

## Build

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen). Don't edit the `.xcodeproj` directly: edit `project.yml` and regenerate.

All commands run from the repo root. After changing `project.yml`, run `just generate` to regenerate the `.xcodeproj`. Use `just build ios`, `just test ios`, and `just --list` for the full command surface.

## Critical files

- `src/eigin_ios/project.yml` — XcodeGen project spec
- `src/eigin_ios/Sources/App/EiginApp.swift` — app entry, ModelContainer, environment injection
- `src/eigin_ios/Sources/App/Container+Services.swift` — Factory DI registrations
- `src/eigin_ios/Sources/App/ToolAssembly.swift` — tool composition from domain kits
- `justfile` — top-level build commands
