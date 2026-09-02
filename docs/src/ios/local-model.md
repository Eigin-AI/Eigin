# Local model

The local model is Gemma 4 E2B, Google's instruction-tuned model, run fully on device through Google's [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) runtime on the GPU/Metal backend with a quantization-aware-trained (2/4/8-bit) mobile build. No server connection.

The runtime wrapper is `GemmaRuntime`, model-agnostic apart from Gemma's sampler defaults and the natural seam for a future generic LiteRT runtime. Gemma's chat formatting lives alongside it: message conversion, the native tool-call wire format, and the output filter.

LiteRT-LM's Swift wrapper is vendored as a local package at `src/eigin_ios/Packages/LiteRTLM` rather than a remote SPM dependency, because of git-LFS checkout failures upstream and a `Conversation.close()` we add locally. See that package's `README.md`.

## The model file

A single `.litertlm` file (~2.6 GB) downloads from Eigin's [model mirror](../runbooks/model-mirror.md)
— not HuggingFace. It's the standard build, which bundles vision and audio
encoders; the runtime loads those on demand, so they cost nothing while only
text is used. The app is text-only today.

| | |
|---|---|
| Download | `GemmaModelDownloader`: background `URLSession`, resumable, parallel, checksum-verified |
| Location | `~/Documents/Models/gemma4-e2b-litertlm/` |
| Backup | Excluded from iCloud/iTunes backups (re-downloadable) |
| Device gate | Requires ≥ 5 GB RAM (iPhone 15 or later); checked before download and load |

## Engine cache

On first load LiteRT-LM compiles its engine graph and caches it under `~/Library/Caches/litert-lm/`. The first load takes a few seconds; later loads on the same device return quickly. The model loads lazily on the first generation request, not at startup.

Multi-token prediction (speculative decoding) is enabled when the build supports it; if engine init fails with it on, the runtime retries once without it, so a model lacking MTP heads still loads.

## Generation

`GemmaRuntime` keeps a persistent LiteRT `Conversation` so prefix caching applies across turns: when a request appends to the held history, only the new turn is sent and the prior KV cache is reused. When the history diverges (new chat, edit, regenerate) the conversation is rebuilt. If history exceeds the context window, the oldest non-system turns are dropped until it fits.

| Setting | Value |
|---|---|
| Context window | 8192 tokens |
| Max output | 512 tokens |
| Sampler | temperature 1.0, top-p 0.95, top-k 64 (Gemma 4 defaults) |

Output streams as it's generated, and is always finalized on completion so the chat layer can commit the message; cancelling the consuming task stops decoding promptly.

LiteRT allows only **one session per engine**, so all generation is serialized through `LiteRTSessionGate`. Requests carry a priority, propagated as a task-local: a foreground send (`.interactive`) preempts and cancels running or queued `.background` work (compaction, title generation), so the user is never blocked behind best-effort jobs.

## Memory eviction

The engine weights (~2 GB on the GPU) and the KV cache stay resident only while the model is in use. `GemmaModelManager` tracks in-flight generations and, once nothing is running, arms a 90 s idle timer; when it fires it fully unloads the engine, freeing both weights and cache. Any generation cancels the timer, so an active chat or call keeps the model loaded. It also unloads immediately on system memory pressure when idle. Without this the session would sit in memory for the app's life and grow with each turn.

## Tool calls

Gemma doesn't use JSON tool calls. Tools are declared, called, and answered with custom markers (`<|tool>`, `<|tool_call>`, `<|tool_response>`) and a custom quoting token. `GemmaToolFormat` translates between that format and the app's OpenAI-style `ToolCall`/JSON, and `GemmaStreamFilter` holds back trailing characters that might start a marker so partial markers never show as prose.
