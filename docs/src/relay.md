# Eigin Relay

Eigin Relay is a connectivity service for Eigin agents. It brokers the few capabilities an agent can't perform on device because they need a server-side key or a stable endpoint. Today that means web search and AI inference.

Using the relay is anonymous. There are no user accounts.

## Search

When the agent searches the web, the query goes to the relay, which forwards it to [Mojeek](https://www.mojeek.com), a privacy-respecting independent search engine, and returns the results. Search draws from a shared usage pool; if it is exhausted, the app falls back to on-device search.

## Inference

The relay forwards inference requests to a vetted upstream provider, so users can run capable models without managing a provider key of their own. Prompt and response content is never logged or stored; the relay reads only the token counts it needs to compute cost.

Inference is gated by credits, and credits are tied to a purchase or a grant instead of a user identity:

- Users buy non-expiring credit packs via IAP, or receive a direct credit grant. Either way, a wallet is created from the proof and identified by a hash of the transaction instead of the person.
- A request is admitted when the wallet has enough balance. Credits are debited after the request completes, based on actual upstream token usage. 1 credit gives you roughly €0.01 of inference at upstream cost.

## Abuse prevention

- A shared key (`x-eigin-key`) gates every request.
- Per-IP rate limiting caps how fast a single client can call.
- Per-purchase rate limiting caps how many devices can consume a single credit pack.
- Shared quota pools bound total usage; when a pool is exhausted, the feature pauses until it resets.

## API

For endpoints and request formats, see the live API docs at <https://relay.eigin.ai/docs>.

## Self-hosting

The relay ships as a Docker image with Terraform to deploy it. If you would rather not use the Eigin instance, run your own with your own keys and no shared limits.
