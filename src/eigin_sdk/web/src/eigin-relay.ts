import {
  EiginRelayProvider,
  uniffiInitAsync,
  type EiginRelayProviderLike,
  type EiginRelayProviderConfig,
  type EiginRelayWalletSource,
  type InferenceCompletionInput,
  type InferenceEvent,
  type HttpTransport,
} from "./generated";
import { FetchTransport } from "./http";
import { withCancellation } from "./cancellation";
import { InferenceEventIterator } from "./inference-stream";

export { EiginRelayWalletError } from "./generated";
export type {
  EiginRelayProviderConfig,
  EiginRelayWalletSource,
} from "./generated";

/** Eigin Relay inference with host-owned wallets and SDK-managed failover. */
export class EiginRelay {
  private constructor(private readonly provider: EiginRelayProviderLike) {}

  static async create(
    config: EiginRelayProviderConfig,
    walletSource: EiginRelayWalletSource,
    transport: HttpTransport = new FetchTransport(),
  ): Promise<EiginRelay> {
    await uniffiInitAsync(
      new URL("./generated/eigin_sdk.wasm", import.meta.url),
    );
    return new EiginRelay(
      EiginRelayProvider.withTransport(config, walletSource, transport),
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

  /** Uses the same cancellable iterator lifecycle as OpenAI-compatible inference. */
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
