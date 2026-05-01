# Introduction

**Eigin is a personal AI agent that lives on your device.** It runs locally, owns its own memory and settings, and talks directly to the inference provider you choose. There is no Eigin account: the agent is yours.

This is the Eigin documentation: what it is, how the pieces fit together, and how native Eigin apps implement them.

## Why Eigin?

Most AI apps are chat sessions wrapped around someone else's account. The provider holds the memory, the data, and the relationship. The user holds a text box.

Eigin is built the other way around. The agent persists, with its own identity, knowledge, and goals. It learns the user across conversations. The data is local. The provider is the user's choice.

## Features

- **A persistent agent.** One per device, with its own identity, knowledge graph, intents, and skills. See [The Agent](./agents/README.md).
- **Local-first.** Chats, knowledge, intents, and settings live on the device. Inference goes from the device to your provider with your API key. See [System context](./system-context.md).
- **Your choice of provider.** Cloud (OpenAI, Anthropic, Google, Mistral, OpenRouter, any OpenAI-compatible API) or fully on-device (Apple Foundation Model). See [Inference providers](./providers.md).
- **Voice.** Local dictation and half-duplex "live calls", built in. See [Voice](./voice/README.md).
- **Free and open source.** Funded by 42futures' enterprise practice. See [Philosophy](./philosophy.md).

## Where to start

If you're new to the codebase, read in this order:

1. [Philosophy](./philosophy.md) — why Eigin exists.
2. [System context](./system-context.md) — Eigin at the system level.
3. [The Agent](./agents/README.md) — the agent ontology: Core, Experience, Knowledge, Intents, Skills.
4. [iOS Implementation](./ios/README.md) — how the iOS app realises those concepts.

Then jump into whatever you're touching: [Conversation](./conversation/README.md), [Tools](./tools/README.md), or [Voice](./voice/README.md).

## Building from source

**Prerequisites:** Xcode (with `xcode-select -s`), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```
make generate   # Regenerate .xcodeproj from project.yml
make build      # Generate + build
make test       # Generate + run unit tests
make open       # Generate + open in Xcode
```
