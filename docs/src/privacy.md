# Privacy and security

Eigin is a powerful agent that works within a strict harness: a permission system, OS platform security, and a local-first data model. It's built on the premise that you own your data, and the apps share as little of it as they can.

## Local-first data

Chats, knowledge, intents, and settings are stored on your device. Data leaves the device in two cases, both under your control.

#### Inference
Generating a reply sends the conversation to whichever engine you choose:

- **Eigin Relay**: a privacy-preserving, European-owned service that proxies AI inference for you.
- **Your own provider**: any OpenAI-compatible provider. Eigin highlights sensible options, though data handling follows each provider's terms.
- **A local model**: runs entirely on-device, so nothing leaves for inference.

#### Connectivity services
A few features, like web search, run through the Eigin Relay because they need a server-side key. The relay is only ever contacted when you use it, and is built to see only the request being made.

## Platform security

When Eigin uses device capabilities (location, reminders, email, microphone) it goes through native OS APIs and their standard permission system. It takes the official route rather than working around access controls.

## On-device processing

Speech recognition, text-to-speech, on-device ML, and tools all run on device. Speech never leaves for processing, and the knowledge base doesn't depend on an external service. See [Voice](./voice/README.md) and [Knowledge](./agents/knowledge.md).

## Tool permissions

A [configurable permission system](./tools/permissions.md) controls what the agent can do. Defaults are conservative: read-only actions are allowed; anything that modifies state or uses external services requires consent.

## Prompt injection

External inputs like web search results and MCP tool responses carry risk of prompt injection: instructions embedded in content that try to hijack the agent. 

Eigin mitigates this in layers:

1. External actions require permission by default; search and MCP tools are ask-before-use unless explicitly allowed.
2. Destructive actions require consent regardless of what triggered them.
3. OS restrictions bound system-level actions.

This doesn't eliminate the risk, but an injection can't silently cause damage: it would have to clear multiple permission gates first.
