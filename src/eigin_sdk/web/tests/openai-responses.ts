import {
  OpenAIResponses,
  InferenceEvent,
  InferenceError,
  type InferenceCompletionInput,
  type InferenceToolCall,
} from "../src";

const input: InferenceCompletionInput = {
  model: "test",
  messages: [
    {
      role: "user",
      content: "hello",
      images: [],
      hasAttachments: false,
      providerMetadata: new Map(),
    },
  ],
  tools: [
    {
      name: "weather",
      description: "Weather",
      parametersJson: '{"type":"object"}',
    },
  ],
  isRelay: false,
  textOnly: false,
};

export const responsesTests = {
  async run(baseUrl: string) {
    const provider = await OpenAIResponses.create({
      baseUrl,
      apiToken: "test-token",
      extraHeaders: new Map(),
    });
    const models = await provider.fetchModels();
    const content: string[] = [];
    const calls: InferenceToolCall[] = [];
    let finished = false;
    let failure: string | undefined;
    window.responsesText = "";
    try {
      for await (const event of provider.stream(input)) {
        if (InferenceEvent.ContentDelta.instanceOf(event)) {
          content.push(event.inner.text);
          window.responsesText = content.join("");
        } else if (InferenceEvent.ToolCall.instanceOf(event))
          calls.push(event.inner.call);
        else if (InferenceEvent.Finished.instanceOf(event)) finished = true;
      }
    } catch (error) {
      if (!InferenceError.instanceOf(error)) throw error;
      failure = error.tag;
    }
    return { models, content, calls, finished, failure };
  },
};
window.responsesTests = responsesTests;

declare global {
  interface Window {
    responsesTests: typeof responsesTests;
    responsesText: string;
  }
}
