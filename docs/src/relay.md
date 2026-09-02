# Eigin Relay

Eigin Relay is a connectivity service for Eigin agents. It brokers the few capabilities an agent can't perform on device because they need a server-side key or a stable endpoint: today, web search and AI inference. The relay cares about valid credit, not who you are: show proof of purchase and you can use it, no account needed.

## Search

Web search queries go to the relay, which forwards them to [Mojeek](https://www.mojeek.com), a privacy-respecting independent search engine, and returns the results. Search draws from a shared usage pool; when it's exhausted, the app falls back to on-device search.

## Inference

The relay forwards inference to a vetted upstream provider, so users can run capable models without their own key. Prompt and response content is never logged or stored; the relay reads only the token counts it needs to compute cost.

Inference is gated by credits, tied to a purchase or grant rather than an identity:

- Users buy non-expiring credit packs via IAP, or receive a direct grant. Either creates a wallet identified by a hash of the transaction, not the person.
- A request is admitted when the wallet has balance. Credits are debited after completion, based on actual upstream token usage. Roughly 1 credit buys €0.01 of inference at upstream cost.

## Model assets

On-device models (the local LLM and the TTS voices) download from a mirror the
relay fronts, not from their original HuggingFace repos. The relay serves a
versioned manifest per asset — file list, SHA-256 checksums, and short-lived
presigned download URLs — and the app verifies every file before use.

This pins each model to an audited version that's always available: upstream
can't mutate or pull files, and there are no third-party rate limits. Which
version is current is a reviewed change in the relay's config, so a swap is a
merge, not a live edit. The mirror is access-controlled by the same shared key
as everything else; if you [self-host](#self-hosting), you run your own bucket
and audit your own uploads.

## Abuse prevention

- A shared key (`x-eigin-key`) gates every request.
- Per-IP rate limiting caps call speed.
- Per-purchase rate limiting caps how many devices consume one credit pack.
- Shared quota pools bound total usage; an exhausted pool pauses the feature until it resets.

## API

See the live API docs at <https://relay.eigin.ai/docs>.

## Self-hosting

The relay ships as a Docker image with Terraform to deploy it. You can self-host to run your own instance with no shared limits.
