import { InferenceError, type InferenceEvent } from "./generated";

type StreamOperation = {
  open(): Promise<void>;
  next(): Promise<InferenceEvent | undefined>;
  cancel(): void;
};

type InferenceRead = IteratorResult<InferenceEvent>;

function endOfStream(): InferenceRead {
  return { done: true, value: undefined };
}

/** Explicit return interrupts pending I/O immediately. */
export class InferenceEventIterator implements AsyncIterableIterator<InferenceEvent> {
  private operation?: StreamOperation;
  private closed = false;
  private pending = false;
  private readonly cancel = () => this.operation?.cancel();

  constructor(
    private readonly create: () => StreamOperation,
    private readonly signal?: AbortSignal,
  ) {}

  [Symbol.asyncIterator](): this {
    return this;
  }

  async next(): Promise<InferenceRead> {
    if (this.closed) return endOfStream();
    if (this.pending) throw InferenceError.Busy.new();

    this.pending = true;
    try {
      return await this.readNextEvent();
    } catch (error) {
      return this.finishAfterError(error);
    } finally {
      this.pending = false;
    }
  }

  async return(): Promise<InferenceRead> {
    this.close();
    return endOfStream();
  }

  private async readNextEvent(): Promise<InferenceRead> {
    this.signal?.throwIfAborted();

    // return() can interrupt either await below.
    const operation = await this.open();
    if (this.closed) return endOfStream();

    const event = await operation.next();
    if (this.closed) return endOfStream();
    this.signal?.throwIfAborted();

    if (event === undefined) {
      this.close();
      return endOfStream();
    }
    return { done: false, value: event };
  }

  private finishAfterError(error: unknown): InferenceRead {
    const alreadyClosed = this.closed;
    this.close();

    if (alreadyClosed) return endOfStream();
    this.signal?.throwIfAborted();
    throw error;
  }

  private async open(): Promise<StreamOperation> {
    if (this.operation) return this.operation;

    const operation = this.create();
    this.operation = operation;
    this.signal?.addEventListener("abort", this.cancel, { once: true });
    await operation.open();
    return operation;
  }

  private close(): void {
    if (this.closed) return;

    this.closed = true;
    this.signal?.removeEventListener("abort", this.cancel);
    this.cancel();
  }
}
