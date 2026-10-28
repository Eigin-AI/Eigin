# The open application layer for personal AI

Eigin is a personal AI agent built to be private, safe and under your control.

[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-2F2D2B)](LICENSE)
[![Platform: iOS 26](https://img.shields.io/badge/platform-iOS%2026-2F2D2B)](https://tally.so/r/rDDpKM)
[![Matrix](https://img.shields.io/badge/chat-Matrix-2F2D2B)](https://chat.eigin.ai)

<img src="docs/src/images/banner.gif" alt="The Eigin blob, surrounded by things people tell it and ask of it: Plan my week around the kids. I feel tired today. Move my 3pm and let Anna know. Why do I always get anxious on Sundays?">

## What would you tell an AI, if you knew it was truly yours?

Our places for reflection used to be private. Now we think out loud with AI, and every word lands on a corporate server.

Technology this personal should belong to the people who use it. That's why we're building Eigin.

![Eigin on iPhone.](docs/src/images/get-eigin.jpg)

[![Join the beta on TestFlight](docs/src/images/testflight-badge.svg)](https://tally.so/r/rDDpKM)

Available on iOS. See what's new in the [changelog](CHANGELOG.md).

## What it does

- **Personal context.** An on-device knowledge graph of your people, goals and routines, with an editable agent character.
- **Model choice.** Use our European cloud AI, connect an OpenAI-compatible provider or run a local model. Your agent and memory stay with you.
- **Connected tools.** Native calendar, reminders and health, plus a library of useful integrations and MCP.
- **Background tasks.** Goals tracked as intents, with scheduled sessions within the permissions you set.
- **Local voice.** On-device speech recognition and text-to-speech, with a hands-free call mode.

## How it works

**Eigin is local-first.** Its agent runtime, memory and tools run on your device. Chats, memories and settings are stored locally. Inference runs locally, through Eigin's private cloud AI or your chosen AI provider.

**Eigin is a closed-set agent.** Its runtime has a fixed set of declared tools, with no shell or virtual computer. It asks before changing your data or acting on your behalf.

**Eigin is yours.** Edit its character and memory, connect your own tools and choose your models. The code is open source, so you can change the application itself and run your own version.

<img src="docs/src/images/system.png" alt="The agent runtime, memory, chats, skills, integrations, voice and local model run on your device. Cloud inference and connected tools send permitted data to external services.">

Read about the [architecture](https://docs.eigin.ai/system-context.html) and [security and compliance](https://docs.eigin.ai/compliance/README.html).

## Build it yourself

Install [Rust](https://rustup.rs) and [just](https://github.com/casey/just#installation). For iOS, you also need macOS, Xcode 26 with the iOS 26 SDK, [XcodeGen](https://github.com/yonaskolb/XcodeGen#installing) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat#how-do-i-install-it).

```sh
just hooks               # install git hooks (one-time)
just config init         # create your .env
just generate            # run code generation
just run ios simulator   # build and launch in the simulator
```

See the [build guide](https://docs.eigin.ai/contributing/build-from-source.html) for setup details.

## Contribute

- Read the [contributing guide](https://docs.eigin.ai/contributing/README.html).
- Open a [bug report](https://code.eigin.ai/dev/eigin/-/issues/new?issuable_template=bug_report) or [feature request](https://code.eigin.ai/dev/eigin/-/issues/new?issuable_template=feature_request).
- Join the conversation on [Matrix](https://chat.eigin.ai).
- Report vulnerabilities through [SECURITY.md](SECURITY.md).

## FAQ

**How is Eigin funded?** The app is free for personal use, funded by optional cloud AI and commercial plans. Local models and your own provider are supported.

**Can I self-host?** The app runs on your device. The optional relay ships as a Docker image with Terraform configuration for deployment.

**What if the terms change?** Code released under AGPL stays available under that license. You can fork it and run your own version.

More in the [FAQ](https://docs.eigin.ai/faq.html).

## License

Eigin is free and open source under [AGPL v3](LICENSE). Third-party attributions are in [`LICENSES/`](LICENSES).
