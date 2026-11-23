# Overview

Eigin SDK is a portable, cross-platform library for Eigin's agent runtime. It is written in Rust, with Swift and browser interfaces.

Hosts provide the user interface, application lifecycle, and platform services. Start with [Getting started](getting-started.md) to connect the SDK to your application.

> The agent runtime is moving from iOS into the SDK. As each domain moves, its concepts and usage documentation will live here. Most runtime behavior still lives in iOS today.

## SDK capabilities

- [Agent turn progression](turn-progression.md): execute tool rounds, recover an interrupted or empty reply, and finish a turn.
- [Turn output and checkpoints](../conversation/agentic-loop.md#safe-checkpoints): report output transitions, map stable provenance to app identities, and retain interrupted work before persistence.

- [Outgoing conversation preparation](conversation-preparation.md): select history and assemble request-only messages.
- [Model catalog](model-catalog.md): resolve offered IDs, choose defaults, and apply model-specific policy.
- [Cloud model routing](model-routing.md): select models using turn requirements, conversation affinity, and health.
- [Inference](inference.md): choose a provider, consume events and manage cancellation.
- [Context paging](../conversation/context-paging.md#sdk): select retained history and tool-result masks.

## Agent concepts

- [The Agent](../agents/README.md): identity, knowledge, skills, and intents.
- [Conversation](../conversation/README.md): the agentic loop, context, and paging.
- [Tools](../tools/README.md): actions, permissions, and MCP.
- [Integrations](../integrations/README.md): connected services and platform capabilities.
- [Voice](../voice/README.md): speech and live interaction.
