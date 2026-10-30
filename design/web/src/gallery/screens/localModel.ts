import type { AssetState } from "@lib";

/** Mirrors the local-model availability explanation shared by iOS screens. */
export const unsupportedDescription = "This device isn’t supported.";
export const hardwareGuidance =
  "Eigin targets iPhone 15 or later for local models. You can still use Eigin with cloud AI.";

/** Download states selectable in the onboarding gallery preview. */
export const downloadStates = {
  "not installed": { kind: "notDownloaded" },
  queued: { kind: "queued" },
  downloading: { kind: "downloading", fractionCompleted: 0.08, estimatedSecondsLeft: 540 },
  downloaded: { kind: "downloaded" },
  preparing: { kind: "preparing" },
  ready: { kind: "ready" },
  failed: { kind: "failed", message: "The download failed. Please try again." },
  "storage blocked": {
    kind: "unavailable",
    reason: "There isn’t enough free storage to download the local model.",
  },
} satisfies Record<string, AssetState>;

export type DownloadStage = keyof typeof downloadStates;
