# Local model

The local model is Gemma 4 E2B — Google's 2-billion parameter Gemma 4 model,
converted to CoreML format and optimised to run on Apple's Neural Engine (ANE).
To fit within the ANE's memory constraints, the model has been split into
several chunks. Each chunk is small enough to be compiled and executed on the
Neural Engine, which gives fast, low-power inference without requiring a GPU or
server connection.

## ANE specialisation

When the app loads a chunk for the first time, CoreML compiles it into a
device-specific binary format optimised for the local hardware. This is called
ANE specialisation. For a model this size it takes several minutes total across
all chunks.

CoreML caches the result. All subsequent loads of the same chunk on the same
device return in seconds.

## What invalidates the cache?

The cache is tied to the file's location on disk, its metadata, and the OS
build. It is discarded when:

| Event | Effect |
|---|---|
| App relaunch / device reboot | Cache survives |
| New build from Xcode (development) | Always re-specialises |
| App Store / TestFlight update | Re-specialises (iOS moves the app to a new path) |
| OS update | Re-specialises (cache is keyed on OS build) |
| Low-disk eviction | Cache may be purged |

## The prewarm pass

To avoid blocking the user's first prompt after an update, the app runs a
prewarm pass in the foreground when the app version changes.

The pass loads and immediately discards each chunk — one at a time, so memory
stays low. It does not load the tokeniser, embeddings, or KV cache. The goal
is only to populate CoreML's cache before the user asks a question.

If the user sends a prompt while the prewarm is still running, the app waits
for it to finish and then loads the model normally — by which point most chunks
are already cached and the load completes in seconds.

The pass runs only once per app version. If the user backgrounds the app
mid-pass, it is cancelled and resumes on the next foreground activation —
chunks already specialised remain in the cache and are skipped on the next run.

## Observability

Per-chunk timings are logged at the `info` level. A cold chunk (first run after
an update) takes tens of seconds; a cached chunk takes milliseconds:

```
GemmaRuntime: prewarm chunk1 in 45321ms   ← cold
GemmaRuntime: prewarm chunk2 in 12ms      ← cached
```

The same format is used during a real model load, making it straightforward to
confirm whether a given load hit the cache.

## iCloud backup

The model directory is excluded from iCloud and iTunes backups. The ~3.8 GB of
weights are re-downloadable and do not belong in a backup.
