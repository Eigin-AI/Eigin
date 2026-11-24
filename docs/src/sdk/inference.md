# Inference

The SDK supports OpenAI-compatible endpoints, OpenAI Responses, native Anthropic Messages, Eigin Relay, and host-provided local models. Your app stores conversations and executes tools. Choose a model directly or use [SDK model routing](model-routing.md).

## Use a provider

1. Create a provider with an endpoint and credentials.
2. Discover models, then start a stream with messages and optional tools.
3. Consume events until completion. Cancel when the user stops.

| Platform | OpenAI-compatible | OpenAI Responses | Anthropic | Eigin Relay |
|---|---|---|---|---|
| Apple | `EiginSDK.Experimental.Inference.OpenAICompatible` | `EiginSDK.Experimental.Inference.OpenAIResponses` | `EiginSDK.Experimental.Inference.Anthropic` | `EiginSDK.Experimental.Inference.EiginRelay` |
| Browser | `OpenAICompatible` | `OpenAIResponses` | `Anthropic` | `EiginRelay` |
| Rust | `OpenAiCompatibleProvider` | `OpenAiResponsesProvider` | `AnthropicProvider` | `EiginRelayProvider` |

The browser package and these inference APIs are experimental. Apple uses your URLSession, browsers use Fetch, and native callers can use SDK-managed HTTP.

For Eigin Relay, supply the relay root URL, application key and an `EiginRelayWalletSource`:

- `next_token(excluded)` supplies a spendable credit token.
- `mark_exhausted(token)` records an exhausted wallet.

The SDK handles switching wallets. Your app owns storage, purchases and balance refresh. Model discovery needs only the application key.

Browser endpoints must allow CORS. Deployed relay browser access remains unverified; only expose credentials intended for browser use.[^anthropic-browser]

[^anthropic-browser]: Direct Anthropic browser requests require `anthropic-dangerous-direct-browser-access: true` in `extraHeaders`. This exposes the supplied key to page code; keep application secrets on a backend. Authenticated browser streaming remains unverified.

## Host-provided local models

The host owns model files, readiness, loading, hardware acceleration, and native sessions. The SDK invokes that capability and delivers the same input/event values and Apple `Stream` interface used by cloud inference.

On Apple, supply a preparation closure to `EiginSDK.Experimental.Inference.Local`:

```swift
let provider = EiginSDK.Experimental.Inference.Local { input, tools in
    let session = try await runtime.prepare(input) // Your host runtime adapter.
    return .init(
        next: { try await session.nextEvent() },
        cancel: { session.cancelGeneration() }
    )
}
let stream = try await provider.stream(input)
defer { stream.cancel() }
while let event = try await stream.next() {
    // Deliver text, tool calls, metadata, or a finished event to your consumer.
}
```

The example's `runtime` converts the SDK input and produces normalized events. Requirements for that adapter:

- Deliver ordered events, including `finished`, then return `nil` at end-of-stream. Throw typed `LocalUnavailable` or `LocalRuntime` failures when execution fails.
- Make cancellation stop native generation and pending host work. Swift task cancellation and stream disposal forward to the SDK operation.
- Serialize access when the native runtime supports only one generation at a time.
- For runtimes with internal tool rounds, pass `executeTool` to `provider.stream`. The preparation closure receives a request-scoped `tools` handle; call `tools.execute(call:)` from the runtime's tool bridge. The supplied closure owns permissions, tool execution, and exchange recording. Native internal rounds remain runtime-owned.

Rust consumers construct `LocalInferenceProvider` with a `LocalInferenceExecutor`, then create a stream, await `open`, consume `next`, and call `cancel`. Executor callbacks start preparation, deliver one event per read, and close a request by ID. Each stream permits one pending operation; use a fresh `LocalToolSession` per request when supplying inline tools.

Use [offline routing](model-routing.md#offline-fallback) to select the capability. Availability can change after selection, so preparation must recheck resources.

## Performance observations

The structured SDK cloud providers emit a typed `Performance` event before `Finished`, including relay, OpenAI-compatible, Responses, and Anthropic streams.

- `time_to_first_token_ms`: HTTP dispatch to first nonempty text or tool output, excluding thinking traces.
- `tokens_per_second`: non-reasoning output tokens divided by first-to-last useful-output time.

Both values are optional. Throughput requires provider-reported reasoning/thinking counts, at least four useful tokens, and a measurable interval. Missing accounting stays absent. Swift exposes TTFT as a native `Duration` through `Performance.timeToFirstToken`.

Measurements are operational events, separate from conversation metadata. The app and relay use these definitions on their respective network paths.

## Try it

Use the experimental CLI with credentials from explicitly named environment variables:

```sh
just run cli experimental inference chat --base-url https://api.openai.com/v1 \
  --api-key-env OPENAI_API_KEY --model YOUR_MODEL --prompt 'Hello'

just run cli experimental inference chat --provider openai-responses \
  --base-url https://api.openai.com/v1 --api-key-env CHATGPT_ACCESS_TOKEN \
  --model YOUR_MODEL --prompt 'Hello'

just run cli experimental inference chat --provider anthropic \
  --base-url https://api.anthropic.com/v1 --api-key-env ANTHROPIC_API_KEY \
  --model YOUR_MODEL --prompt 'Hello'

just run cli experimental inference chat --provider eigin-relay \
  --base-url https://YOUR_RELAY --relay-key-env EIGIN_RELAY_KEY \
  --credit-token-env EIGIN_WALLET --model YOUR_MODEL --prompt 'Hello'
```

- Use `models` instead of `chat` to list models; omit `--model` and `--prompt`.
- Repeat `--credit-token-env` to supply wallets in spending order. CLI wallets are held in memory.
- Use `--no-auth` for an unauthenticated OpenAI-compatible endpoint.
- Press Ctrl-C to cancel.

See [provider selection](../providers.md) for model catalogs and routing.
