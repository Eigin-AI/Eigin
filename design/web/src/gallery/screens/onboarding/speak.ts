import { StreamThrottler, driveFrames } from "@lib";
import { WORD_INTERVAL_MS } from "@gallery/screens/onboarding/opening";

/** Resolves after `ms`, or as soon as `signal` aborts. */
export function pause(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    signal.addEventListener("abort", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

/**
 * Streams `text` word by word through the chat's throttler, so a scripted line
 * reads as the agent saying it. Calls `onText` with the revealed prefix.
 */
export async function speak(
  text: string,
  onText: (shown: string) => void,
  signal: AbortSignal,
): Promise<void> {
  const throttler = new StreamThrottler();
  throttler.start();
  let stop = () => {};

  const words = text.split(" ").map((word, index) => (index === 0 ? word : ` ${word}`));
  for (const [index, word] of words.entries()) {
    if (signal.aborted) break;
    throttler.feed(word);
    if (index === 0) {
      stop = driveFrames(
        (now) => {
          throttler.tick(now);
          onText(throttler.displayedText);
        },
        () => throttler.isRunning && !signal.aborted,
      );
    }
    await pause(WORD_INTERVAL_MS, signal);
  }
  throttler.finish();

  while (throttler.phase !== "done" && !signal.aborted) await pause(16, signal);
  stop();
  if (!signal.aborted) onText(text);
}
