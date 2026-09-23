# Introduction

<p class="tagline">The open application layer for personal AI</p>

Eigin is a capable personal agent that belongs to you.

<img src="images/banner.gif" alt="The Eigin blob, surrounded by things people tell it and ask of it: Plan my week around the kids. I feel tired today. Move my 3pm and let Anna know. Why do I always get anxious on Sundays?">

To get real value from AI, you have to let it know you. How you think, what you care about, your private conversations.

Most personal AI today belongs to someone else, and answers to them.

Eigin lives on your device and answers only to you. You choose the model and how it works.

## What makes Eigin different

| What you get | In practice |
| --- | --- |
| **It shapes itself around you** | No baked-in persona. It builds an on-device knowledge graph of your people, goals and routines. See [The Agent](./agents/README.md). |
| **You own your context** | Chats and memory live on your device. Use any OpenAI-compatible API, a local model, or [Eigin Relay](./relay.md) with no account. See [Inference providers](./providers.md). |
| **It integrates with your life** | Native calendar, reminders, health and location, plus Gmail, Microsoft and IMAP. MCP covers the rest. See [Integrations](./integrations/README.md). |
| **It works while you're away** | It tracks your goals as intents and follows up in scheduled background sessions. See [Initiative](./agents/initiative.md). |
| **Its voice stays local** | On-device speech recognition, local text-to-speech and a hands-free live call mode. See [Voice](./voice/README.md). |
| **It's built for people** | A fixed set of declared tools and no shell. It asks before changing your data or acting on your behalf. See [Permissions](./tools/permissions.md). |
| **It's open and compliant** | AGPL v3, compliant with GDPR and the EU AI Act, with a CASA-validated relay. See [Compliance](./compliance/README.md). |

## Where to start

New to the codebase? Read in order:

1. [Philosophy](./philosophy.md): why Eigin exists.
2. [System context](./system-context.md): Eigin at the system level.
3. [The Agent](./agents/README.md): the agent ontology.
4. [Contributing](./contributing/README.md): how we work, and how to get involved.

Then jump to whatever you're working on: [iOS](./ios/README.md), [Conversation](./conversation/README.md), [Tools](./tools/README.md), or [Voice](./voice/README.md).

## Building from source

See [Build from source](./contributing/build-from-source.md) for prerequisites, setup, and build commands.
