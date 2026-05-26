# Introduction

**Eigin is the application layer for personal AI:** a persistent agent that runs on your device, connects any AI inference provider you want, and builds knowledge about you across every conversation.

These are the technical docs for Eigin: what it is, how it works, and how its implemented.

## Features

- **Persistent agent.** One per device, with its own identity, knowledge graph, intents, and skills. See [The Agent](./agents/README.md).
- **Local-first.** Chats, knowledge, intents, and settings live on the device. See [System context](./system-context.md).
- **Model-agnostic.** Cloud (any OpenAI-compatible API) or fully local. See [Inference providers](./providers.md).
- **Voice.** On-device dictation and a live call mode for hands-free conversation. See [Voice](./voice/README.md).
- **Free and open source.** See [Philosophy](./philosophy.md).

## Where to start

If you're new to the codebase, read in this order:

1. [Philosophy](./philosophy.md) — why Eigin exists.
2. [System context](./system-context.md) — Eigin at the system level.
3. [The Agent](./agents/README.md) — the agent ontology: Core, Experience, Knowledge, Intents, Skills.
4. [iOS Implementation](./ios/README.md) — how the iOS app realises those concepts.

Then jump into whatever you're touching: [Conversation](./conversation/README.md), [Tools](./tools/README.md), or [Voice](./voice/README.md).

## Building from source

This is a monorepo containing all Eigin applications. Install dependencies for the platform you want to work on.

**iOS:**

- Xcode — `xcode-select -s /Applications/Xcode.app/Contents/Developer`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) — `brew install swiftformat`

**Relay:**

- [Rust and Cargo](https://rustup.rs) — via rustup

**Command runner (required for all platforms):**

- [just](https://just.systems) — `brew install just`

After cloning, run `just hooks` once to install git hooks. Then use `just build`, `just test`, and `just format`, scoped by platform if needed:

```
just build          # All targets
just build ios      # iOS only
just build relay    # Relay only
```

Run `just --list` to see all available commands.
