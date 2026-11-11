import type {
  HttpTransport,
  HttpRequest,
  HttpResponseHeadCallbackLike,
  HttpBodyChunkCallbackLike,
} from "./generated";

type Exchange = {
  abort: AbortController;
  reader?: ReadableStreamDefaultReader<Uint8Array>;
  remaining?: Uint8Array;
};

/** Browser-managed TLS/proxies, omitted ambient credentials and 60-second I/O waits. */
export class FetchTransport implements HttpTransport {
  private readonly exchanges = new Map<bigint, Exchange>();

  startRequest(
    id: bigint,
    request: HttpRequest,
    completion: HttpResponseHeadCallbackLike,
  ): void {
    const exchange: Exchange = { abort: new AbortController() };
    this.exchanges.set(id, exchange);
    void this.withTimeout(exchange, async () => {
      try {
        const response = await fetch(request.url, {
          method: request.method,
          headers: Object.fromEntries(request.headers),
          body: request.body.byteLength ? request.body : undefined,
          signal: exchange.abort.signal,
          credentials: "omit",
          // Fetch cannot safely inspect a manual cross-origin redirect before following it.
          redirect: "error",
        });
        exchange.reader = response.body?.getReader();
        completion.succeed({
          status: response.status,
          headers: new Map(response.headers.entries()),
        });
      } catch (error) {
        completion.fail(String(error));
      }
    });
  }

  read(id: bigint, completion: HttpBodyChunkCallbackLike): void {
    const exchange = this.exchanges.get(id);
    if (!exchange) {
      completion.fail("HTTP response closed");
      return;
    }
    void this.withTimeout(exchange, async () => {
      try {
        if (!exchange.remaining?.byteLength) {
          const next = await exchange.reader?.read();
          if (!next || next.done) {
            completion.succeed(undefined);
            return;
          }
          exchange.remaining = next.value;
        }
        if (exchange.remaining.byteLength > 1024 * 1024) {
          completion.fail("HTTP chunk exceeds 1 MiB");
          this.close(id);
          return;
        }
        const bytes = exchange.remaining.slice(0, 64 * 1024);
        exchange.remaining = exchange.remaining.subarray(bytes.byteLength);
        completion.succeed(bytes.buffer);
      } catch (error) {
        completion.fail(String(error));
      }
    });
  }

  close(id: bigint): void {
    const exchange = this.exchanges.get(id);
    this.exchanges.delete(id);
    exchange?.abort.abort();
    void exchange?.reader?.cancel().catch(() => {});
  }

  private async withTimeout(exchange: Exchange, work: () => Promise<void>) {
    const timeout = setTimeout(
      () =>
        exchange.abort.abort(
          new DOMException("HTTP idle timeout", "TimeoutError"),
        ),
      60_000,
    );
    try {
      await work();
    } finally {
      clearTimeout(timeout);
    }
  }
}
