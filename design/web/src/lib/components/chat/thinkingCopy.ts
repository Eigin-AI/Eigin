/** The copy ladder the figure speaks up with as a wait drags on. */

export type ThinkingCopy =
  "thinking" | "stillThinking" | "almostThere" | "takingAWhile" | "sorryForTheWait";

const rungs: ThinkingCopy[] = [
  "thinking",
  "stillThinking",
  "almostThere",
  "takingAWhile",
  "sorryForTheWait",
];

/** Seconds to wait before each rung appears. */
export const thresholds = [4.5, 11, 18, 29, 44];

/** English copy; the app supplies its own translations. */
export const thinkingText: Record<ThinkingCopy, string> = {
  thinking: "Thinking",
  stillThinking: "Still thinking",
  almostThere: "Almost there",
  takingAWhile: "Taking a while",
  sorryForTheWait: "Sorry to keep you waiting",
};

export const waitingForYouText = "Waiting for you";

/** The rung at `t` seconds since the indicator appeared, or null while silent. */
export function stageAt(t: number): ThinkingCopy | null {
  for (let i = 0; i < thresholds.length; i++) {
    if (t < thresholds[i]) continue;
    if (i + 1 >= thresholds.length || t < thresholds[i + 1]) return rungs[i];
  }
  return null;
}
