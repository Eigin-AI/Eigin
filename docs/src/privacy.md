# Privacy and security
Eigin is designed to be a responsible AI assistant for your device. The agent is powerful, but it works in a strict harness: a permission system, OS platform security, and a local-first data model.

## Local-first data
Eigin data lives on your device. There is no Eigin account and no Eigin-hosted data store: chats, knowledge, intents, and settings never go to a 42futures server. You can read, edit, delete, or export that data. Delete the app and *all of it* is gone.

Data leaves your device in two situations, both under your control:

1. **Inference calls.** When the agent generates a reply, it calls the provider you configured. The request goes from your device to that provider with your API key. Eigin is not in the middle. You choose which providers to trust — GDPR-compliant providers with zero retention, a specific vendor you trust, or fully on-device inference via Apple Foundation Model.
2. **Eigin Relay (optional).** A small 42futures-operated service that brokers narrow third-party features the app can't ship to every user. Today: web search. The relay only sees the request your agent makes (e.g. a search query). It does not see chat content, your knowledge base, or any personal data. If your agent never uses a relay-backed feature, the relay is never contacted.

## Platform security
When Eigin interacts with your device (location, reminders, email, microphone) it goes through OS native APIs. This means the OS standard permission model applies: you'll be asked whether to allow access.

Eigin doesn't try to work around these restrictions. It doesn't do sneaky stuff or access data that it shouldn't. It takes the official route, using APIs that have access controls already baked in.

## On-device processing
Transcription, text-to-speech, and knowledge embeddings all run on device by default. Speech never leaves the device for processing, and the agent's knowledge base isn't sent to an external service. See [Voice](./voice/README.md) and [Knowledge](./agents/knowledge.md) for details.

## Tool permissions
The agent has a [configurable permission system](./tools/permissions.md) that controls what it's allowed to do. 

The defaults are conservative: read-only actions are allowed, while anything that modifies state or touches external services requires user consent. See [Permissions](./tools/permissions.md) for more.

## Prompt injection
External inputs like web search results carry a risk of prompt injection. Eigin mitigates this in stages:

1. External inputs require user permission by default: users approve each action
2. Any destructive action that could be triggered by injected instructions is also subject to user consent by default
3. OS platform restrictions provide a further boundary for system-level actions

This doesn't eliminate the risk entirely, but it means a prompt injection won't silently cause damage: it would need to get past multiple permission gates first.
