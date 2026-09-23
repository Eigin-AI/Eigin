# Inference providers

Eigin treats inference as a utility. The agent doesn't care which model is on the other end, as long as it can hold a conversation and call tools. All provider communication flows through a single client protocol, with a few implementations covering the landscape, so switching providers is easy. Three kinds sit behind that protocol: the Eigin Relay, third-party cloud providers, and on-device local models.

## Eigin Relay

A built-in provider backed by Eigin's cloud inference proxy. It's the easiest way to connect cloud AI: buy credits with an in-app purchase and start chatting. Behind the scenes it forwards requests to a vetted upstream provider. See [Eigin Relay](./relay.md).

## Cloud providers

Bring your own key to a third-party provider. Built-in presets: OpenAI, Anthropic, Google (AI Studio), Mistral, OpenRouter, EUrouter, Berget, Infercom. Each preset bundles a base URL, logo, help text, and a link to get an API key. You can also add a custom provider with any OpenAI-compatible base URL.

## Local providers

Inference can run entirely on-device: offline, on your own hardware. The local provider is a built-in preset, picked like any other. Once downloaded, a model stands in for cloud models in normal chats.

## Clients

Rather than a client per provider, Eigin uses a small set:

- **OpenAI-compatible client**: any provider implementing the OpenAI REST API (`/models`, `/chat/completions`). Covers OpenAI, Google, Mistral, OpenRouter, and most others.
- **Relay client**: the OpenAI-compatible client pointed at the [Eigin Relay](./relay.md), plus credit-wallet management. No API key: each request is authorized with a credit token instead.
- **Anthropic client**: a native implementation for the Messages API, which differs enough to warrant its own client (auth headers, content blocks, typed SSE events, system prompt handling).
- **Local client**: bridges the agent loop to the on-device model, holding session state per chat.

A factory selects the client from the base URL: the relay URL routes to the relay client, other cloud URLs to OpenAI or Anthropic, and `local://` to the on-device client. Adding an OpenAI-compatible provider is just adding a preset.

## Provider adapters

Some providers are mostly OpenAI-compatible but have quirks. A provider adapter handles the adjustments instead of branching inside the client:

- **Gemini**: sends `stop` as the finish reason even with tool calls present. The adapter checks for pending tool calls on stop and injects Gemini-specific metadata.
- **Mistral**: requires tool call IDs to be alphanumeric and at most 9 characters. The adapter sanitizes them.
- **Anthropic on OpenRouter**: injects a `cache_control` hint so OpenRouter passes prompt caching through.

## Model catalog

A curated list of known models with metadata: display names, context windows, costs, and capabilities (tool calls, reasoning, vision), ranked by fit. The catalog is what routing ranks against, and what the model selector renders.

## Model routing

When **Automatic** model selection is enabled, a router picks which of the provider's models runs each turn. Picking a specific model turns routing off.

The router is asked before a turn is built, since the prompt budget and tool registry are sized from the model that runs. After the turn it receives performance metrics, and how the turn ended.

The chat loop sends requirements to the router (like whether it needs vision), and the router resolves that to a model based on best-effort. Requirements get progressively relaxed until a model can be found.

Rejected keys, empty wallets, and malformed requests still appear as errors to the user instead.

### Offline

On Automatic, with no network and an on-device model downloaded, the turn runs locally. A user-selected cloud model fails in this scenario.

The detour isn't persisted: the agent's provider and model still point at the best cloud model choice, so the next connected turn returns there.

## Extending

- **New OpenAI-compatible provider**: add a preset.
- **Provider with quirks**: add a preset and an adapter.
- **Completely different API**: implement the client protocol and add a URL check in the factory.
- **New models or re-ranking**: update the catalog.
