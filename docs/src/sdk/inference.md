# Inference

The SDK supports OpenAI-compatible endpoints, OpenAI Responses, and Eigin Relay. Your app chooses models, stores conversations and executes tools.

## Use a provider

1. Create a provider with an endpoint and credentials.
2. Discover models, then start a stream with messages and optional tools.
3. Consume events until completion. Cancel when the user stops.

| Platform | OpenAI-compatible | OpenAI Responses | Eigin Relay |
|---|---|---|---|
| Apple | `EiginSDK.Experimental.Inference.OpenAICompatible` | `EiginSDK.Experimental.Inference.OpenAIResponses` | `EiginSDK.Experimental.Inference.EiginRelay` |
| Browser | `OpenAICompatible` | `OpenAIResponses` | `EiginRelay` |
| Rust | `OpenAiCompatibleProvider` | `OpenAiResponsesProvider` | `EiginRelayProvider` |

The browser package and these inference APIs are experimental. Apple uses your URLSession, browsers use Fetch, and native callers can use SDK-managed HTTP.

For Eigin Relay, supply the relay root URL, application key and an `EiginRelayWalletSource`:

- `next_token(excluded)` supplies a spendable credit token.
- `mark_exhausted(token)` records an exhausted wallet.

The SDK handles switching wallets. Your app owns storage, purchases and balance refresh. Model discovery needs only the application key.

Browser endpoints must allow CORS. Deployed relay browser access remains unverified; only expose credentials intended for browser use.

## Try it

Use the experimental CLI with credentials from explicitly named environment variables:

```sh
just run cli experimental inference chat --base-url https://api.openai.com/v1 \
  --api-key-env OPENAI_API_KEY --model YOUR_MODEL --prompt 'Hello'

just run cli experimental inference chat --provider openai-responses \
  --base-url https://api.openai.com/v1 --api-key-env CHATGPT_ACCESS_TOKEN \
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
