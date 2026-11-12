import {
  EiginRelay,
  InferenceError,
  InferenceEvent,
  type InferenceCompletionInput,
  type InferenceToolCall,
} from "../src";

const input: InferenceCompletionInput = {
  model: "test",
  messages: [
    {
      role: "user",
      content: "Say hello and check the weather",
      images: [],
      hasAttachments: false,
      providerMetadata: new Map(),
    },
  ],
  tools: [
    {
      name: "weather",
      description: "Get weather",
      parametersJson:
        '{"type":"object","properties":{"city":{"type":"string"}}}',
    },
  ],
  isRelay: false,
  textOnly: false,
};

export const relayTests = {
  async invalidConfiguration() {
    try {
      await EiginRelay.create(
        { baseUrl: "https://configuration.test", relayKey: "" },
        {
          nextToken() {
            throw new Error("Construction must not select a wallet");
          },
          markExhausted() {
            throw new Error("Construction must not exhaust a wallet");
          },
        },
      );
      return false;
    } catch (error) {
      return InferenceError.EiginRelayNotConfigured.instanceOf(error);
    }
  },

  async run(baseUrl: string) {
    const exhausted: string[] = [];
    let selections = 0;
    const provider = await EiginRelay.create(
      { baseUrl, relayKey: "relay-key" },
      {
        nextToken(excluded) {
          selections++;
          return ["first", "second"].find((t) => !excluded.includes(t));
        },
        markExhausted(token) {
          exhausted.push(token);
        },
      },
    );
    const models = await provider.fetchModels();
    const discoverySelections = selections;
    const content: string[] = [];
    const calls: InferenceToolCall[] = [];
    let finished = false;
    let eventCount = 0;
    let failure: { kind: string; status?: number } | undefined;
    window.relayText = "";
    try {
      for await (const event of provider.stream(input)) {
        eventCount++;
        if (InferenceEvent.ContentDelta.instanceOf(event)) {
          content.push(event.inner.text);
          window.relayText = content.join("");
        } else if (InferenceEvent.ToolCall.instanceOf(event)) {
          calls.push(event.inner.call);
        } else if (InferenceEvent.Finished.instanceOf(event)) {
          finished = true;
        }
      }
    } catch (error) {
      if (!InferenceError.instanceOf(error)) throw error;
      failure = { kind: error.tag };
      if (InferenceError.Http.instanceOf(error))
        failure.status = error.inner.status;
    }
    return {
      models,
      discoverySelections,
      exhausted,
      eventCount,
      selections,
      content,
      calls,
      finished,
      failure,
    };
  },
};
window.relayTests = relayTests;
