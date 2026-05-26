# Eigin Relay

Eigin Relay is a free connectivity service operated by Eigin. It brokers features that require reaching external services - things the app can't do on its own because they need a server-side API key or a persistent endpoint.

## Anonymous by design

Using the relay is anonymous. There is no user identifier attached to requests. The app sends a shared key with each request, but its only purpose is to keep non-Eigin clients out.

## What it does today

**Web search.** When the agent uses the web search tool, the query goes to the relay, which forwards it to [Mojeek](https://www.mojeek.com) and returns the results. Mojeek is a privacy-respecting, independent search engine.

## What's next

Connectivity that requires a stable, reachable endpoint: agent-to-agent communication, device synchronization, backup, and potentially inference. The relay expands as Eigin does, within the same constraint: it sees only what it needs to fulfil the request.

## Abuse prevention

Three layers gate the relay:

1. **Shared key.** Every request carries a key in a header (`x-eigin-key`). This raises the bar for casual abuse - you have to have the key. Requests without it are rejected immediately.

2. **Per-IP rate limiting.** A sliding window limits how many requests a single IP can make in a given period.

3. **Community pool.** Relay-backed features draw from a shared monthly quota. If the pool is exhausted, those features become unavailable until it resets. Since the relay is optional, this is an acceptable outcome - and for search specifically, the app falls back to on-device search.

## Self-hosting

The relay ships as a Docker image. If you'd rather not rely on the Eigin instance, you can run it yourself with your own API keys and no shared limits. The repository includes Terraform code to deploy it to the cloud.
