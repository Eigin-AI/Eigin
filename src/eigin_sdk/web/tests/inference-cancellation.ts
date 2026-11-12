import {
  EiginRelay,
  OpenAICompatible,
  OpenAIResponses,
  type InferenceCompletionInput,
} from "../src";

const input: InferenceCompletionInput = {
  model: "test",
  messages: [],
  isRelay: false,
  textOnly: false,
};

function assert(value: boolean, reason: string): asserts value {
  if (!value) throw new Error(reason);
}

/** Stalls at the Fetch boundary; tests only host cancellation, not provider responses. */
async function withStalledFetch(
  phase: "headers" | "body",
  run: (ready: Promise<void>, aborted: () => boolean) => Promise<void>,
) {
  const original = globalThis.fetch;
  let started!: () => void;
  const ready = new Promise<void>((resolve) => {
    started = resolve;
  });
  let aborted = false;
  globalThis.fetch = async (url, options) => {
    // WASM loading still uses the ordinary browser resource fetch.
    if (!String(url).startsWith("https://cancellation.test")) {
      return original(url, options);
    }
    const signal = options?.signal;
    return new Promise<Response>((resolve, reject) => {
      signal?.addEventListener(
        "abort",
        () => {
          aborted = true;
          reject(new DOMException("Cancelled", "AbortError"));
        },
        { once: true },
      );
      if (phase === "headers") {
        started();
      } else {
        resolve(
          new Response(
            new ReadableStream<Uint8Array>({
              pull() {
                started();
              },
            }),
          ),
        );
      }
    });
  };
  try {
    await run(ready, () => aborted);
  } finally {
    globalThis.fetch = original;
  }
}

async function provider(
  kind: "openai-compatible" | "eigin-relay" | "openai-responses",
) {
  if (kind === "eigin-relay")
    return EiginRelay.create(
      { baseUrl: "https://cancellation.test", relayKey: "relay-key" },
      {
        nextToken(excluded) {
          return excluded.length ? undefined : "token";
        },
        markExhausted() {
          throw new Error("Cancellation must not exhaust a wallet");
        },
      },
    );
  return (
    kind === "openai-responses" ? OpenAIResponses : OpenAICompatible
  ).create({
    baseUrl: "https://cancellation.test/v1",
    apiToken: "test",
    extraHeaders: new Map(),
  });
}

export const providerTests = {
  async returnInterruptsPendingRead() {
    for (const kind of [
      "openai-compatible",
      "eigin-relay",
      "openai-responses",
    ] as const) {
      for (const phase of ["headers", "body"] as const) {
        await withStalledFetch(phase, async (ready, aborted) => {
          const stream = (await provider(kind)).stream(input);
          const pending = stream.next();
          await ready;
          await stream.return!();
          assert(
            (await pending).done === true,
            "return must finish a pending next",
          );
          assert(aborted(), "return must abort Fetch");
        });
      }
    }
  },

  async discoveryCancellation() {
    for (const providerType of [OpenAICompatible, OpenAIResponses]) {
      for (const validate of [false, true]) {
        await withStalledFetch("headers", async (ready, aborted) => {
          const client = await providerType.create({
            baseUrl: "https://cancellation.test/v1",
            apiToken: "test",
            extraHeaders: new Map(),
          });
          const controller = new AbortController();
          const pending = validate
            ? client.validateAPIKey("test", controller.signal)
            : client.fetchModels(controller.signal);
          const rejected = pending.then(
            () => false,
            () => true,
          );
          await ready;
          controller.abort();
          assert(await rejected, "aborted operation must reject");
          assert(aborted(), "operation cancellation must abort Fetch");
        });
      }
    }
  },
};

window.providerTests = providerTests;
