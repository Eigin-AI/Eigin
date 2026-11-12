import { withCancellation } from "./cancellation";
import {
  OpenAiCompatibleProvider,
  OpenAiResponsesProvider,
  type OpenAiResponsesProviderLike,
  InferenceError,
  uniffiInitAsync,
  type OpenAiCompatibleProviderLike,
  type InferenceProviderConfig,
  type InferenceCompletionInput,
  type InferenceEvent,
  type HttpTransport,
} from "./generated";
import { InferenceEventIterator } from "./inference-stream";
import { FetchTransport } from "./http";

export {
  InferenceError,
  InferenceEvent,
  InferenceFinishReason,
  InferenceModelFamily,
} from "./generated";
export type {
  InferenceProviderConfig,
  InferenceCompletionInput,
  InferenceMessage,
  InferenceImage,
  InferenceToolCall,
  InferenceToolDefinition,
  InferenceReasoningHistory,
  InferenceReasoningOrigin,
  HttpTransport,
} from "./generated";
export { FetchTransport } from "./http";

/** Browser wrapper for the Rust provider. CORS and endpoint credentials remain host concerns. */
export class OpenAICompatible {
  private constructor(
    private readonly provider: OpenAiCompatibleProviderLike,
  ) {}

  static async create(
    config: InferenceProviderConfig,
    transport: HttpTransport = new FetchTransport(),
  ): Promise<OpenAICompatible> {
    await uniffiInitAsync(
      new URL("./generated/eigin_sdk.wasm", import.meta.url),
    );
    return new OpenAICompatible(
      OpenAiCompatibleProvider.withTransport(config, transport),
    );
  }

  async fetchModels(signal?: AbortSignal): Promise<string[]> {
    const operation = this.provider.discovery();
    return withCancellation(
      () => operation.cancel(),
      signal,
      () => operation.fetchModels(),
    );
  }

  async validateAPIKey(model: string, signal?: AbortSignal): Promise<void> {
    const operation = this.provider.keyValidation();
    return withCancellation(
      () => operation.cancel(),
      signal,
      () => operation.validateApiKey(model),
    );
  }

  /** Break/return cancels even a pending read. AbortSignal interrupts pending I/O. */
  stream(
    input: InferenceCompletionInput,
    signal?: AbortSignal,
  ): AsyncIterableIterator<InferenceEvent> {
    return new InferenceEventIterator(
      () => this.provider.stream(input),
      signal,
    );
  }
}

/** Browser wrapper for the Rust provider. CORS and endpoint credentials remain host concerns. */
export class OpenAIResponses {
  private constructor(private readonly provider: OpenAiResponsesProviderLike) {}

  static async create(
    config: InferenceProviderConfig,
    transport: HttpTransport = new FetchTransport(),
  ): Promise<OpenAIResponses> {
    await uniffiInitAsync(
      new URL("./generated/eigin_sdk.wasm", import.meta.url),
    );
    return new OpenAIResponses(
      OpenAiResponsesProvider.withTransport(config, transport),
    );
  }

  async fetchModels(signal?: AbortSignal): Promise<string[]> {
    const operation = this.provider.discovery();
    return withCancellation(
      () => operation.cancel(),
      signal,
      () => operation.fetchModels(),
    );
  }

  async validateAPIKey(model: string, signal?: AbortSignal): Promise<void> {
    const operation = this.provider.keyValidation();
    return withCancellation(
      () => operation.cancel(),
      signal,
      () => operation.validateApiKey(model),
    );
  }

  /** Break/return cancels even a pending read. AbortSignal interrupts pending I/O. */
  stream(
    input: InferenceCompletionInput,
    signal?: AbortSignal,
  ): AsyncIterableIterator<InferenceEvent> {
    return new InferenceEventIterator(
      () => this.provider.stream(input),
      signal,
    );
  }
}
