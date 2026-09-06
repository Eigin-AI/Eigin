/** Mirrors `AssetState`: every stage of getting an on-device asset in place. */
export type AssetState =
  | { kind: "notDownloaded" }
  | { kind: "queued" }
  | { kind: "downloading"; fractionCompleted: number; estimatedSecondsLeft?: number }
  | { kind: "downloaded" }
  | { kind: "preparing"; fractionCompleted?: number }
  | { kind: "ready" }
  | { kind: "failed"; message: string }
  | { kind: "unavailable"; reason: string };

/**
 * Human time left, as short as it can be: "42 s left", "12 min left",
 * "1 h 5 min left". Rounded up, so it never shows a confident-looking zero.
 */
export function timeLeftText(seconds?: number): string | undefined {
  if (seconds === undefined || seconds < 1) return undefined;
  if (seconds < 60) return `${Math.ceil(seconds)} s left`;
  if (seconds < 3600) return `${Math.ceil(seconds / 60)} min left`;
  return `${Math.floor(seconds / 3600)} h ${Math.ceil((seconds % 3600) / 60)} min left`;
}
