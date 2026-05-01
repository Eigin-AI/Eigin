# Eigin Relay

Eigin Relay is a free connectivity service operated by 42futures. It brokers features that require reaching external services — things the app can't do on its own because they need a server-side API key or a persistent endpoint for other parties to connect to.

Eigin can offer this for free because the relay is cheap to run. It does almost nothing: receive a request, validate it, forward it, return the result. No processing, no storage, no user data. The infrastructure cost is low enough that 42futures absorbs it entirely.

## Anonymous by design

Using the relay is anonymous. There is no account, no user identifier, nothing that ties a request to a person. The app does send a shared key with each request, but its only purpose is to keep non-Eigin clients out — not to identify who is asking.

## What it does today

**Web search.** When the agent uses the web search tool, the query goes to the relay, which forwards it to [Mojeek](https://www.mojeek.com) and returns the results. Mojeek is a privacy-respecting, independent search engine. The relay holds the Mojeek API key; the app does not.

## What's next

Connectivity that requires a stable, reachable endpoint — agent-to-agent discovery, agents contacting each other, cross-device sync — will go through the relay. The relay expands as Eigin does, within the same constraint: it sees only what it needs to fulfil the request.

## Abuse prevention

Three layers gate the relay:

1. **Shared key.** Every request carries a key in a header (`x-eigin-key`). Its purpose is to keep non-Eigin clients out, not to identify users. Requests without it are rejected immediately.

2. **Per-IP rate limiting.** A sliding window limits how many requests a single IP can make in a given period. IP state is held in memory only and is never written to disk — it is evicted naturally as the window expires.

3. **Community pool.** Paid features like web search draw from a shared monthly quota. When the pool is exhausted, those features are unavailable until the month resets. The pool is funded by 42futures. If search runs out, the agent falls back to on-device search.

The pool is intentional. It keeps the financial risk of offering a free service bounded, while keeping the experience seamless for the vast majority of users. The relay is generous by design; the pool is the ceiling.

## Self-hosting

The relay ships as a Docker image. If you'd rather not rely on the 42futures instance — or want your own API keys and no shared pool — you can run it yourself. Point it at your own Mojeek key, set the pool size to whatever you like, and you have a dedicated instance with no shared limits.

Configuring Eigin to use a custom relay URL is planned but not yet available in the app. For now, the app points at the 42futures instance.
