# Introduction

<p class="tagline">The open application layer for personal AI</p>

Eigin is a personal AI agent built to be private, safe and under your control.

<img src="images/banner.gif" alt="The Eigin blob, surrounded by things people tell it and ask of it: Plan my week around the kids. I feel tired today. Move my 3pm and let Anna know. Why do I always get anxious on Sundays?">

## What would you tell an AI, if you knew it was truly yours?

Our places for reflection used to be private. Now we think out loud with AI, and every word lands on a corporate server.

Technology this personal should belong to the people who use it. That's why we're building Eigin.

![Eigin on iPhone.](images/get-eigin.jpg)

## What it does

- **Personal context.** An on-device knowledge graph of your people, goals and routines, with an editable agent character. See [The Agent](./agents/README.md).
- **Model choice.** Use our European cloud AI, connect an OpenAI-compatible provider or run a local model. Your agent and memory stay with you. See [Inference providers](./providers.md) and [Eigin Relay](./relay.md).
- **Connected tools.** Native calendar, reminders and health, plus a library of useful integrations and MCP. See [Integrations](./integrations/README.md).
- **Background tasks.** Goals tracked as intents, with scheduled sessions within the permissions you set. See [Initiative](./agents/initiative.md).
- **Local voice.** On-device speech recognition and text-to-speech, with a hands-free call mode. See [Voice](./voice/README.md).

## How it works

**Eigin is local-first.** Its agent runtime, memory and tools run on your device. Chats, memories and settings are stored locally. Inference runs locally, through Eigin's private cloud AI or your chosen AI provider.

**Eigin is a closed-set agent.** Its runtime has a fixed set of declared tools, with no shell or virtual computer. It asks before changing your data or acting on your behalf. See [Permissions](./tools/permissions.md).

**Eigin is yours.** Edit its character and memory, connect your own tools and choose your models. The code is open source, so you can change the application itself and run your own version.

Read about the [architecture](./system-context.md) and [security and compliance](./compliance/README.md).

## Where to start

New to the codebase? Read in order:

1. [Philosophy](./philosophy.md): why Eigin exists.
2. [System context](./system-context.md): Eigin at the system level.
3. [The Agent](./agents/README.md): the agent ontology.
4. [Contributing](./contributing/README.md): how we work, and how to get involved.

Then jump to whatever you're working on: [iOS](./ios/README.md), [Conversation](./conversation/README.md), [Tools](./tools/README.md), or [Voice](./voice/README.md).

## Building from source

See [Build from source](./contributing/build-from-source.md) for prerequisites, setup, and build commands.
