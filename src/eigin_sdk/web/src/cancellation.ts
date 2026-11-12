export async function withCancellation<T>(
  cancel: () => void,
  signal: AbortSignal | undefined,
  work: () => Promise<T>,
): Promise<T> {
  signal?.addEventListener("abort", cancel, { once: true });
  try {
    signal?.throwIfAborted();
    const result = await work();
    signal?.throwIfAborted();
    return result;
  } catch (error) {
    signal?.throwIfAborted();
    throw error;
  } finally {
    signal?.removeEventListener("abort", cancel);
    cancel();
  }
}
