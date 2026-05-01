# Inference providers

Eigin treats inference providers like utilities: pick one, plug it in, go. The agent doesn't care which model is on the other end as long as it can hold a conversation and call tools.

## Why this design

The provider system exists to make switching providers trivial. Users shouldn't be locked in. The architecture reflects that: a single client protocol that all provider communication flows through, with a small number of implementations covering the landscape — cloud and local.

## Cloud providers

Eigin ships with eight built-in cloud presets:

- **OpenAI**
- **Anthropic**
- **Google** (AI Studio)
- **Mistral**
- **OpenRouter**
- **EUrouter**
- **Scaleway**
- **OVHcloud**

Each preset bundles a base URL, logo, help text, and a link to get an API key. Users can also add custom providers with any OpenAI-compatible base URL.

A provider is a persistent record storing the user's configuration — name, base URL, available models, and which models they've enabled. Cloud requests go from the device to the provider with no Eigin proxy in between.

## Local providers

Some inference happens entirely on-device. Local providers don't need an API key or internet, and never leave the device.

- **Apple Foundation Model** — Apple Intelligence's on-device model via the system `FoundationModels` framework. The primary local option on iOS today. It's a built-in preset alongside the cloud ones, and the user picks it the same way.

Local providers use a different client under the hood — they talk to the OS, not an HTTP endpoint — but that's invisible to the rest of the app.

## The client strategy

Rather than building a client per provider, Eigin uses a small set of client implementations:

**OpenAI-compatible client** — works with any provider implementing the OpenAI REST API (`/models`, `/chat/completions`). This covers OpenAI, Google, Mistral, OpenRouter, and most others with a single implementation.

**Anthropic client** — a native implementation for Anthropic's Messages API, which differs enough to warrant its own client (different auth headers, content block format, typed SSE events, system prompt handling).

**Foundation Model client** — for on-device Apple inference. Bridges the agent loop to Apple's `LanguageModelSession` API, holding session state per chat so the model retains its built-in transcript.

A factory selects the client from the base URL: cloud URLs route to the OpenAI or Anthropic client, `local://` URLs route to the on-device client. Adding a new OpenAI-compatible provider is just adding another preset.

## Provider adapters

Some providers are *mostly* OpenAI-compatible but have quirks. Rather than branching inside the client, a provider adapter protocol handles provider-specific adjustments:

- **Gemini** sends `stop` as the finish reason even when tool calls are present. The adapter tells the stream parser to check for pending tool calls on "stop". It also injects Gemini-specific metadata (`thought_signature`).
- **Mistral** requires tool call IDs to be alphanumeric and at most 9 characters. The adapter sanitizes IDs before they're sent.
- **Default** no-op, for standard providers.

The adapter is selected based on the provider URL.

## Model catalog

The model catalog is a curated list of known models with metadata like display names, context windows, costs, and capabilities (tool calls, reasoning, vision). This lets the UI show meaningful information without extra network calls. 

Models are matched by ID prefix with normalization so the same catalog entry works across providers that use slightly different IDs for the same model.

## How to extend

**New OpenAI-compatible provider:** Add a preset.

**Provider with quirks:** Add a preset and a provider adapter implementation.

**Completely different API:** Implement the client protocol and add a URL check in the factory.
