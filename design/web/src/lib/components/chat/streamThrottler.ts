/**
 * Paces streamed assistant text so it reads as typing rather than arriving in
 * bursts.
 *
 * Text is never appended as it lands. Each tick closes a fraction of the gap to
 * the buffered text — `1 - exp(-rate · dt)` — so reveal speed is the same
 * whatever the tick cadence, and a fast model reveals in larger chunks instead
 * of looking jumpy. The display snaps back to the last completed word, so line
 * breaking never reflows a half-typed one.
 *
 * A port of `StreamThrottler.swift`. Time is injected and `tick` is public, so
 * the whole reveal can be stepped by hand.
 */
export type StreamPhase = "idle" | "waiting" | "streaming" | "done";

export interface StreamThrottlerOptions {
  /**
   * Continuous catch-up coefficient, per second. Higher reveals faster and in
   * larger chunks.
   */
  catchUpRate?: number;
  /**
   * How long the stream may sit quiet, with everything buffered already
   * scanned, before the tail is revealed even mid-word. Slow models often send
   * their last delta seconds before the finish event; without this the final
   * word would hide for that whole window.
   */
  stallGrace?: number;
  /** Clock in seconds, in the same timebase as the timestamps passed to `tick`. */
  now?: () => number;
}

/** Publish a scroll cue every N ticks that revealed text. */
const SCROLL_EVERY = 6;

/** Nominal tick interval, assumed for the first tick when there's no prior one. */
const NOMINAL_INTERVAL = 1 / 30;

export class StreamThrottler {
  phase: StreamPhase = "idle";
  displayedText = "";
  fullText = "";
  scrollTrigger = 0;

  private inputCount = 0;
  private displayedCount = 0;
  /**
   * Monotonic catch-up cursor. It advances every tick regardless of word
   * boundaries and `displayedCount` snaps back to the last whole word at or
   * under it. Keeping them apart lets the display stay word-aligned while the
   * cursor still always reaches the end, so the drain can't stall on a
   * trailing partial word.
   */
  private scanCount = 0;
  private serverDone = false;
  private tickCount = 0;
  private lastTickTime = 0;
  private lastFeedTime = 0;

  private readonly catchUpRate: number;
  private readonly stallGrace: number;
  private readonly now: () => number;

  constructor({
    catchUpRate = 2,
    stallGrace = 0.45,
    now = () => performance.now() / 1000,
  }: StreamThrottlerOptions = {}) {
    this.catchUpRate = catchUpRate;
    this.stallGrace = stallGrace;
    this.now = now;
  }

  /** True while the throttler still has work for the driver to tick. */
  get isRunning(): boolean {
    return this.phase === "streaming";
  }

  start(): void {
    this.reset();
    this.phase = "waiting";
  }

  feed(chunk: string): void {
    if (this.phase === "waiting") {
      this.phase = "streaming";
      this.lastTickTime = 0;
    }
    this.fullText += chunk;
    this.inputCount += chunk.length;
    this.lastFeedTime = this.now();
  }

  /** The server has sent everything; the display may still be catching up. */
  finish(): void {
    this.serverDone = true;
    if (this.displayedCount >= this.inputCount) this.completeDisplay();
  }

  /**
   * Completes the display immediately when the server is done but the driver
   * has stopped ticking — a backgrounded tab. On screen this would skip the
   * typing animation.
   */
  flushIfStalled(): void {
    if (this.serverDone && this.phase === "streaming") this.completeDisplay();
  }

  abort(): void {
    this.phase = "idle";
  }

  reset(): void {
    this.resetKeepingPhase("idle");
  }

  /**
   * Clears the buffers but lands in the given phase. Use `waiting` between
   * tool-call rounds to keep the thinking indicator up.
   */
  resetKeepingPhase(targetPhase: StreamPhase): void {
    this.phase = targetPhase;
    this.displayedText = "";
    this.fullText = "";
    this.inputCount = 0;
    this.displayedCount = 0;
    this.scanCount = 0;
    this.scrollTrigger = 0;
    this.serverDone = false;
    this.tickCount = 0;
    this.lastTickTime = 0;
    this.lastFeedTime = 0;
  }

  /** Advances the reveal. `timestamp` is in seconds. */
  tick(timestamp: number): void {
    const dt =
      this.lastTickTime > 0 ? Math.max(0, timestamp - this.lastTickTime) : NOMINAL_INTERVAL;
    this.lastTickTime = timestamp;

    const distance = this.inputCount - this.scanCount;
    if (distance <= 0) {
      if (this.serverDone) {
        this.completeDisplay();
      } else if (
        this.inputCount > this.displayedCount &&
        this.now() - this.lastFeedTime >= this.stallGrace
      ) {
        this.revealStalledTail();
      }
      return;
    }

    // Scale the advance by real elapsed time, so reveal speed doesn't depend on
    // how often this fires.
    const fraction = 1 - Math.exp(-this.catchUpRate * dt);
    const advance = Math.max(1, Math.round(distance * fraction));
    this.scanCount = Math.min(this.scanCount + advance, this.inputCount);
    const candidate = this.fullText.slice(0, this.scanCount);

    let revealed: string;
    if (this.serverDone && this.scanCount >= this.inputCount) {
      // Nothing more is coming and the cursor is at the end: reveal everything,
      // including the final, possibly partial, word.
      revealed = candidate;
    } else {
      const words = wholeWords(candidate);
      // No completed word in range yet — wait for the cursor to advance.
      if (words === undefined) return;
      revealed = words;
    }

    if (revealed.length <= this.displayedCount) return;
    this.displayedCount = revealed.length;
    this.displayedText = revealed;

    this.tickCount += 1;
    if (this.tickCount % SCROLL_EVERY === 0) this.scrollTrigger += 1;

    if (this.serverDone && this.displayedCount >= this.inputCount) this.completeDisplay();
  }

  /**
   * Reveals everything buffered, partial trailing word included. Runs when the
   * cursor has caught up but the stream has been quiet: the word is fully
   * received, so holding it back reads as a hang.
   */
  private revealStalledTail(): void {
    this.scanCount = this.inputCount;
    this.displayedCount = this.inputCount;
    this.displayedText = this.fullText;
  }

  private completeDisplay(): void {
    if (this.displayedText !== this.fullText) this.displayedText = this.fullText;
    this.displayedCount = this.inputCount;
    this.scanCount = this.inputCount;
    this.phase = "done";
  }
}

/**
 * Trims a streamed prefix back to its last completed word, so a half-typed word
 * is never shown. Undefined when no whole word is available yet.
 */
export function wholeWords(candidate: string): string | undefined {
  for (let i = candidate.length - 1; i >= 0; i--) {
    if (/\s/.test(candidate[i])) return candidate.slice(0, i + 1);
  }
  return undefined;
}
