# Inference providers

Eigin treats AI inference as a utility: plug it in and go. The agent doesn't care which model is on the other end as long as it can hold a conversation and call tools.

## Why this design

The provider system exists to make switching providers easy. Users should be free to choose. The architecture reflects that: a single client protocol that all provider communication flows through, with a small number of implementations covering the landscape.

## Cloud providers

Eigin ships with built-in cloud presets:

- **OpenAI**
- **Anthropic**
- **Google** (AI Studio)
- **Mistral**
- **OpenRouter**
- **EUrouter**
- **Berget**
- **Infercom**

Each preset bundles a base URL, logo, help text, and a link to get an API key. Users can also add custom providers with any OpenAI-compatible base URL.

## Local providers

Inference can happen entirely on-device. No API key or network needed. The local provider is a built-in preset and the user picks it the same way as a cloud provider. Once a model has been downloaded, it can be used in place of cloud models in normal chats.

Small language models are improving quickly, but are still limited in long-context reasoning and tool calling. For now, the local model drives the onboarding flow, a guided conversation that works well within those constraints, and serves as a fallback for offline use.

Local model workflows don't currently support tool calls. An agent running on a local model can answer questions but can't build knowledge, set intents, or take actions. We see this as an area for development. Local models are getting more capable, and making them more useful in Eigin is something we're actively thinking about.

## The client strategy

Rather than building a client per provider, Eigin uses a small set of client implementations:

**OpenAI-compatible client** works with any provider implementing the OpenAI REST API (`/models`, `/chat/completions`). This covers OpenAI, Google, Mistral, OpenRouter, and most others with a single implementation.

**Anthropic client** is a native implementation for Anthropic's Messages API, which differs enough to warrant its own client (different auth headers, content block format, typed SSE events, system prompt handling).

**Local model client** bridges the agent loop to the on-device model, holding session state per chat.

A factory selects the client from the base URL: cloud URLs route to the OpenAI or Anthropic client, `local://` URLs route to the on-device client. Adding a new OpenAI-compatible provider is just adding another preset.

## Provider adapters

Some providers are mostly OpenAI-compatible but have quirks. Rather than branching inside the client, a provider adapter protocol handles provider-specific adjustments:

- **Gemini** sends `stop` as the finish reason even when tool calls are present. The adapter tells the stream parser to check for pending tool calls on "stop". It also injects Gemini-specific metadata (`thought_signature`).
- **Mistral** requires tool call IDs to be alphanumeric and at most 9 characters. The adapter sanitizes IDs before they're sent.
- **Anthropic on OpenRouter** injects a `cache_control` hint into the request body so OpenRouter passes it through to the Anthropic API for prompt caching.
- **Default** no-op, for standard providers.

## Model catalog

The model catalog is a curated list of known models with metadata like display names, context windows, costs, and capabilities (tool calls, reasoning, vision). Models are ranked by fit for the application.

When a user adds a provider, Eigin uses the catalog to automatically select the best fit model. The user can always open the model selector and pick a specific one.

## How to extend

**New OpenAI-compatible provider:** Add a preset.

**Provider with quirks:** Add a preset and a provider adapter implementation.

**Completely different API:** Implement the client protocol and add a URL check in the factory.

**New models or re-ranking:** Update the model catalog with the new entry or adjust the ranking of existing ones.
