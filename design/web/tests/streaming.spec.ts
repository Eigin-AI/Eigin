import { expect, test } from "@playwright/test";
import { stageAt } from "../src/lib/components/chat/thinkingCopy";
import { StreamThrottler } from "../src/lib/components/chat/streamThrottler";
import { ChasingProgress } from "../src/lib/components/chat/chasingProgress";

test.describe("thinking copy", () => {
  test("climbs its rungs on the Swift thresholds", () => {
    expect(stageAt(0)).toBeNull();
    expect(stageAt(4.4)).toBeNull();
    expect(stageAt(4.5)).toBe("thinking");
    expect(stageAt(10.9)).toBe("thinking");
    expect(stageAt(11)).toBe("stillThinking");
    expect(stageAt(18)).toBe("almostThere");
    expect(stageAt(29)).toBe("takingAWhile");
    expect(stageAt(44)).toBe("sorryForTheWait");
    // The last rung holds for the rest of the wait.
    expect(stageAt(600)).toBe("sorryForTheWait");
  });
});

test.describe("stream throttler", () => {
  const paragraph = "The quick brown fox jumps over the lazy dog and keeps running for a while. ";

  /** Steps the reveal at a fixed cadence, returning every distinct frame. */
  function reveal(throttler: StreamThrottler, seconds: number, clock: { t: number }) {
    const frames: string[] = [];
    const step = 1 / 30;
    for (let elapsed = 0; elapsed < seconds; elapsed += step) {
      clock.t += step;
      throttler.tick(clock.t);
      const last = frames[frames.length - 1];
      if (throttler.displayedText !== last) frames.push(throttler.displayedText);
    }
    return frames;
  }

  test("reveals only whole words while the stream is open", () => {
    const clock = { t: 0 };
    const throttler = new StreamThrottler({ now: () => clock.t });
    throttler.start();
    throttler.feed(paragraph);

    const frames = reveal(throttler, 2, clock);

    expect(frames.length).toBeGreaterThan(3);
    for (const frame of frames) {
      // Every frame ends on a word boundary and is a prefix of the source.
      expect(paragraph.startsWith(frame)).toBe(true);
      expect(frame).toMatch(/\s$/);
    }
  });

  test("reveal speed does not depend on tick cadence", () => {
    function revealedAfter(step: number) {
      const clock = { t: 0 };
      const throttler = new StreamThrottler({ now: () => clock.t });
      throttler.start();
      throttler.feed(paragraph.repeat(4));
      for (let elapsed = 0; elapsed < 1; elapsed += step) {
        clock.t += step;
        throttler.tick(clock.t);
      }
      return throttler.displayedText.length;
    }

    // Ticking twice as often must not reveal twice as much.
    const slow = revealedAfter(1 / 15);
    const fast = revealedAfter(1 / 60);
    expect(Math.abs(fast - slow) / slow).toBeLessThan(0.15);
  });

  test("releases a stalled tail rather than hiding the last word", () => {
    const clock = { t: 0 };
    const throttler = new StreamThrottler({ stallGrace: 0.45, now: () => clock.t });
    throttler.start();
    // No trailing space: the last word can never complete on its own.
    throttler.feed("Checking the calendar");

    // Still inside the grace: the trailing word stays hidden, whatever the
    // cursor has scanned.
    reveal(throttler, 0.3, clock);
    expect(throttler.displayedText).toMatch(/\s$/);
    expect(throttler.displayedText).not.toContain("calendar");

    // Once the stream has been quiet past the grace and the cursor has caught
    // up, the tail is safe to show.
    clock.t += 0.2;
    reveal(throttler, 1, clock);
    expect(throttler.displayedText).toBe("Checking the calendar");
  });

  test("finishing completes the text even mid-word", () => {
    const clock = { t: 0 };
    const throttler = new StreamThrottler({ now: () => clock.t });
    throttler.start();
    throttler.feed("Done and dusted");
    throttler.finish();

    reveal(throttler, 3, clock);
    expect(throttler.displayedText).toBe("Done and dusted");
    expect(throttler.phase).toBe("done");
  });

  test("a backgrounded tab flushes instead of freezing mid-sentence", () => {
    const clock = { t: 0 };
    const throttler = new StreamThrottler({ now: () => clock.t });
    throttler.start();
    throttler.feed("Half revealed text here");
    throttler.finish();
    throttler.flushIfStalled();

    expect(throttler.displayedText).toBe("Half revealed text here");
    expect(throttler.phase).toBe("done");
  });
});

test.describe("chasing progress", () => {
  test("travels toward a jumped target at a capped speed", () => {
    const chaser = new ChasingProgress(0.7);
    chaser.setTarget(1);

    let t = 0;
    chaser.tick((t += 0.1));
    // A jump to 1 must not land in one frame.
    expect(chaser.value).toBeLessThan(0.2);

    const first = chaser.value;
    chaser.tick((t += 0.1));
    expect(chaser.value).toBeGreaterThan(first);
    expect(chaser.value - first).toBeLessThanOrEqual(0.7 * 0.1 + 1e-6);
  });

  test("finishes only once the value catches up to a completed target", () => {
    const chaser = new ChasingProgress();
    chaser.setTarget(1);
    let t = 0;

    chaser.tick((t += 0.5));
    expect(chaser.isFinished).toBe(false);

    for (let i = 0; i < 10; i++) chaser.tick((t += 0.5));
    expect(chaser.value).toBe(1);
    expect(chaser.isFinished).toBe(true);
  });

  test("never runs past its target", () => {
    const chaser = new ChasingProgress();
    chaser.setTarget(0.25);
    let t = 0;
    for (let i = 0; i < 20; i++) chaser.tick((t += 0.2));
    expect(chaser.value).toBeCloseTo(0.25, 6);
    expect(chaser.isFinished).toBe(false);
  });
});
