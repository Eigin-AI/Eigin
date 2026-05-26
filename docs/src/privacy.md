# Privacy and security

Eigin is designed to be a responsible AI agent for your device. The agent is powerful, but it works within a strict harness: a permission system, OS platform security, and a local-first data model. The Eigin apps have no tracking, telemetry, or analytics.

## Local-first data

Eigin data lives on your device. Chats, knowledge, intents, and settings are stored locally and not sent to Eigin servers.

Data leaves your device in two situations, both under your control:

1. **Inference calls.** When the agent generates a reply, it calls the provider you configured. The request goes from your device to that provider with your API key. You choose which providers to trust - GDPR-compliant providers with zero data retention, a specific vendor you trust, or a fully on-device local model.
2. **Eigin Relay (optional).** A connectivity service that brokers narrow third-party features. The relay is built around only seeing the specific request being made - nothing else. If your agent never uses a relay-backed feature, the relay is never contacted.

## Platform security

When Eigin interacts with your device - location, reminders, email, microphone - it goes through OS native APIs. The OS standard permission model applies: you'll be asked whether to allow access.

Eigin doesn't try to work around these restrictions. It takes the official route, using APIs that have access controls baked in that users are already familiar with.

## On-device processing

Speech recognition, text-to-speech, on-device machine learning, and tools all run on the device. Speech doesn't leave the device for processing, and the agent's knowledge base doesn't rely on an external service. See [Voice](./voice/README.md) and [Knowledge](./agents/knowledge.md) for details.

## Tool permissions

The agent has a [configurable permission system](./tools/permissions.md) that controls what it's allowed to do.

Permission defaults are conservative: read-only actions are allowed, while anything that modifies state or touches external services requires user consent. See [Permissions](./tools/permissions.md) for more.

## Prompt injection

External inputs like web search results and MCP tool responses carry a risk of prompt injection - instructions embedded in external content that attempt to hijack the agent's behaviour.

Eigin mitigates this in stages:

1. External actions require user permission by default. Search and MCP tools are ask-before-use unless explicitly allowed
2. Destructive actions are subject to user consent by default, no matter what triggered them
3. OS platform restrictions provide a further boundary for system-level actions

This doesn't eliminate the risk entirely, but a prompt injection won't silently cause damage. It would need to get past multiple permission gates first.
