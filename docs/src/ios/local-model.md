# Local model

The local model is Gemma 4 E2B — Google's instruction-tuned Gemma 4 model — run
fully on device through Google's [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM)
runtime. Inference uses the GPU/Metal backend with a quantization-aware-trained
(QAT, 2/4/8-bit) mobile build, giving fast on-device generation with no server
connection.

The runtime wrapper is `GemmaRuntime`; it is model-agnostic apart from Gemma's
sampler defaults and is the natural seam for a future generic LiteRT runtime.
Gemma's chat formatting lives alongside it: message conversion
(`GemmaMessageConversion`), the native tool-call wire format (`GemmaToolFormat`),
and the output filter (`GemmaStreamFilter`).

LiteRT-LM's Swift wrapper is vendored as a local package at
`src/eigin_ios/Packages/LiteRTLM` rather than pulled in as a remote SPM
dependency — see that package's `README.md` for why (git-LFS checkout
failures upstream, and an explicit `Conversation.close()` we add locally).

## The model file

A single `.litertlm` file (~2.6 GB) is downloaded from the
[litert-community](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm)
HuggingFace repo. It is the standard build, which bundles vision and audio
encoders; the runtime loads those on demand, so they cost nothing while only text
is used. The app currently uses text only.

| | |
|---|---|
| Download | `GemmaModelDownloader` — background `URLSession`, resumable, parallel transfers |
| Location | `~/Documents/Models/gemma4-e2b-litertlm/` |
| Backup | Excluded from iCloud/iTunes backups (re-downloadable) |
| Device gate | Requires ≥ 5 GB RAM (iPhone 15 or later); checked before download and load |

## Engine cache

On first load LiteRT-LM compiles its engine graph and caches it under
`~/Library/Caches/litert-lm/`. The first load takes a few seconds; subsequent
loads on the same device return quickly from the cache. The model is loaded
lazily on the first generation request, not at app startup.

Multi-token prediction (speculative decoding) is enabled when the build supports
it; if engine initialization fails with it on, the runtime retries once without
it so a model lacking MTP heads still loads.

## Generation

`GemmaRuntime` keeps a persistent LiteRT `Conversation` so prefix caching applies
across turns: when a request simply appends to the history already held, only the
new turn is sent and the prior KV cache is reused. When the history diverges (new
chat, edit, or regenerate) the conversation is rebuilt. If the history is too long
for the context window, the oldest non-system turns are dropped and the
conversation rebuilt until it fits.

| Setting | Value |
|---|---|
| Context window | 8192 tokens |
| Max output | 512 tokens |
| Sampler | temperature 1.0, top-p 0.95, top-k 64 (Gemma 4 model-card defaults) |

Output streams as it is generated. The stream is always finalized on completion
so the chat layer can commit the message; cancelling the consuming task stops
native decoding promptly.

LiteRT allows only **one session per engine**, so all generation is serialized
through `LiteRTSessionGate` — concurrent requests would otherwise fail with
`A session already exists`. Requests carry a priority (`LocalGeneration.priority`,
propagated as a task-local): a foreground chat send (`.interactive`) preempts and
cancels running or queued `.background` work (compaction, title generation) so the
user is never blocked behind best-effort jobs.

## Memory eviction

The engine weights (~2 GB on the GPU) and the conversation's KV cache stay
resident only while the model is in use. `GemmaModelManager` tracks in-flight
generations and, once nothing is running, arms an idle timer (90 s); when it
fires it fully unloads the engine — freeing both the weights and the KV cache.
Any generation cancels the timer, so an active chat or live call keeps the model
loaded. The model reloads lazily (a few seconds) on the next request. The manager
also unloads immediately on system memory pressure when idle. Without this the
session would sit in memory for the life of the app and grow with each turn.

## Tool calls

Gemma does not use JSON tool calls. Tools are declared, called, and answered using
custom markers (`<|tool>`, `<|tool_call>`, `<|tool_response>`) and a custom
quoting token. `GemmaToolFormat` translates between that format and the app's
OpenAI-style `ToolCall`/JSON, and `GemmaStreamFilter` holds back any trailing
characters that might be the start of a marker so partial markers are never shown
as prose.

## Observability

Per-turn throughput is logged at the `info` level. Note the count is of stream
chunks, not tokens — with multi-token prediction a chunk may carry several
tokens:

```
Gemma: 128 chunks, 2100ms (61.0 chunks/s)
```
