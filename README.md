# The open application layer for personal AI

Eigin is a capable personal agent that belongs to you.

[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-2F2D2B)](LICENSE)
[![Platform: iOS 26](https://img.shields.io/badge/platform-iOS%2026-2F2D2B)](https://apps.apple.com/app/eigin/id6801064030)
[![Matrix](https://img.shields.io/badge/chat-Matrix-2F2D2B)](https://chat.eigin.ai)

<img src="docs/src/images/banner.gif" alt="The Eigin blob, surrounded by things people tell it and ask of it: Plan my week around the kids. I feel tired today. Move my 3pm and let Anna know. Why do I always get anxious on Sundays?">

## What would you tell an AI that's truly yours?

To get real value from AI, you have to let it know you. *Really know you.* How you think, what you care about. Your patterns, your private conversations. The more it knows, the more useful it becomes. And the more personal it gets.

People send more than *50 million personal messages to AI agents every day.* Those agents belong to someone else, and answer to them.

**Eigin belongs to you.** It lives on your device and answers only to you. You choose the model and how it works.

Because it's yours, you can tell it anything. That's how Eigin becomes an AI made for just one person: **you**.

![Get your hands on a hands off AI.](docs/src/images/get-eigin.jpg)

[![App Store](https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg)](https://apps.apple.com/app/eigin/id6801064030)

We're early and moving fast, so see what's new in the [changelog](CHANGELOG.md).

## What makes Eigin different

A capable agent for your whole life, shaped around you and working on your terms.

| What you get | In practice |
| --- | --- |
| **It shapes itself around you** | No baked-in persona. It builds an on-device knowledge graph of your people, goals and routines, and its character is yours to edit or delete. |
| **You own your context** | Chats and memory live on your device. Bring a key for any OpenAI-compatible API, run a local model, or use our European relay with no account and no prompt logging. |
| **It integrates with your life** | Native calendar, reminders, health and location, plus external integrations like Gmail, Microsoft and IMAP. MCP covers the rest, A2A on the way. |
| **It works while you're away** | It tracks your goals as intents and follows up in scheduled background sessions, within the permissions you set. |
| **Its voice stays local** | On-device speech recognition and local text-to-speech models, with a hands-free live call mode. |
| **It's built for people** | A strict runtime with a fixed set of declared tools and no shell. It asks before changing your data or acting on your behalf.|

Dig deeper in the [docs](https://docs.eigin.ai).

## How it works

We built Eigin so you don't have to trust us.

It's **local-first**: your agent, its memory and its tools run on your device, and only the conversation you're having goes to the model you pick.

It's **strict by default**, with you in the loop for anything that matters.

It's **compliant** with GDPR and the EU AI Act, and our relay is CASA validated by an independent lab. See [Compliance](https://docs.eigin.ai/compliance/README.html).

And **all of our source code is open**, so you can check for yourself.

<img src="docs/src/images/system.png" alt="Your agent, with its memory, chats, skills, integrations, voice and local model, lives on your device. Only inference goes to the model you choose, and search goes through the optional Eigin Relay.">

Want the details? [Check our docs](https://docs.eigin.ai/system-context.html).

## Build it yourself

Everything you need is here. Install [Rust](https://rustup.rs) and [just](https://github.com/casey/just#installation) to get started. For the iOS app, add macOS with Xcode 17, [XcodeGen](https://github.com/yonaskolb/XcodeGen#installing) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat#how-do-i-install-it).

```sh
just hooks               # install git hooks (one-time)
just config init         # create your .env
just generate            # run code generation
just run ios simulator   # build and launch in the simulator
```

Read our [full guide](https://docs.eigin.ai/contributing/build-from-source.html) for more.

## Build it with us

We're building for a future where personal AI is private, secure and truly yours. If you want that future too, we'd love your help.

- **Say hi** on our [Matrix](https://chat.eigin.ai) chat server.
- **Found a bug or have an idea?** Open a [bug report](https://code.eigin.ai/dev/eigin/-/issues/new?issuable_template=bug_report) or a [feature request](https://code.eigin.ai/dev/eigin/-/issues/new?issuable_template=feature_request).
- **Want to contribute?** Start with our [contributing guide](https://docs.eigin.ai/contributing/README.html).
- **Found a vulnerability?** See [SECURITY.md](SECURITY.md).

## FAQ

| Question | Answer |
| --- | --- |
| **How is it different from OpenClaw or Hermes?** | They're power-user tools you set up on a server. Eigin is a native app you just download, and it's safe to use by default. |
| **How is it different from Muse or Spark?** | They run on their company's servers, under their terms. Eigin runs on your device, works with any model, and keeps you in the loop. |
| **Can I trust it?** | Eigin uses a strict agent runtime with fixed tools and no shell. It asks before changing your data or acting for you. We trade some capability for safety. |
| **How do you make money?** | The app is free. We take a margin on AI inference via Eigin Relay (optional), but most revenue comes from adapting Eigin for orgs and institutions. |
| **Can I self-host?** | The app already runs on your device, and you can fork it. The relay ships as a Docker image with Terraform so you can own that, too. |
| **What if you change the deal?** | There's no lock-in. Your data stays your own, the code is AGPL, and everything we've shipped under those terms stays that way. |

More answers [here](https://docs.eigin.ai/faq.html).

## License

Eigin is free and open source under [AGPL v3](LICENSE). Third-party attributions are in [`LICENSES/`](LICENSES).
