# Inference

An inference provider sends messages to a model and streams back text and tool calls. The SDK handles the provider protocol; your app chooses models, stores conversations and executes tools.

The SDK currently supports OpenAI-compatible endpoints, including compatible routers. Other provider implementations remain in the host apps.

## Use a provider

1. Create an `OpenAICompatible` provider with an endpoint URL and credentials.
2. Discover models, then create a stream with a model ID, messages and optional tool definitions.
3. Consume events until completion. Cancel when the user stops; retain any partial output if the stream fails.

Apple uses your URLSession; browser clients use Fetch and require endpoint CORS support. Native callers get SDK-managed HTTP.

- **Swift:** `EiginSDK.Experimental.Inference.OpenAICompatible` — the low-level API is experimental.
- **Browser:** `OpenAICompatible` from `@eigin/sdk`.
- **Rust:** `OpenAiCompatibleProvider` in `eigin_sdk::inference::openai_compatible`.

## Try it

Choose credentials explicitly with `--api-key-env NAME`, or use `--no-auth` for an unauthenticated endpoint. The named variable must be set and nonempty.

```sh
just run cli inference models --base-url https://api.openai.com/v1 \
  --api-key-env OPENAI_API_KEY
just run cli inference chat --base-url https://api.openai.com/v1 \
  --api-key-env OPENAI_API_KEY --model YOUR_MODEL --prompt 'Hello'
```

Ctrl-C cancels the request. See [provider selection](../providers.md) for model catalogs and routing.
