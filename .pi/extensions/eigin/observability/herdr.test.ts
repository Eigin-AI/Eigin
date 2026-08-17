/**
 * Unit tests for observability/herdr.ts (plain node --experimental-strip-types, no framework).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { emitHerdrBlocked, withHerdrBlocked } from "./herdr.ts";

function test(name: string, fn: () => void | Promise<void>): void {
  Promise.resolve()
    .then(fn)
    .then(() => console.log(`✓ ${name}`))
    .catch((err) => {
      console.error(`✗ ${name}`);
      console.error(err);
      process.exitCode = 1;
    });
}

function assertEqual<T>(actual: T, expected: T, message?: string): void {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`${message ?? "assertion failed"}: expected ${expectedJson}, got ${actualJson}`);
  }
}

type Emitted = { event: string; payload: unknown };

/** Minimal fake capturing only the event-bus emit calls this module uses. */
function fakePi(): { pi: ExtensionAPI; emitted: Emitted[] } {
  const emitted: Emitted[] = [];
  const pi = {
    events: { emit: (event: string, payload: unknown) => emitted.push({ event, payload }) },
  } as unknown as ExtensionAPI;
  return { pi, emitted };
}

test("emitHerdrBlocked(true) carries the label; false drops it", () => {
  const { pi, emitted } = fakePi();
  emitHerdrBlocked(pi, true, "Answer questions");
  emitHerdrBlocked(pi, false);
  assertEqual(emitted, [
    { event: "herdr:blocked", payload: { active: true, label: "Answer questions" } },
    { event: "herdr:blocked", payload: { active: false } },
  ]);
});

test("withHerdrBlocked brackets the run with balanced active:true / active:false", async () => {
  const { pi, emitted } = fakePi();
  const result = await withHerdrBlocked(pi, "Over to you", async () => {
    // The block is active for the duration of the run.
    assertEqual(emitted, [{ event: "herdr:blocked", payload: { active: true, label: "Over to you" } }]);
    return 42;
  });
  assertEqual(result, 42, "returns the run's value");
  assertEqual(emitted.length, 2, "emits exactly one true and one false");
  assertEqual(emitted[1], { event: "herdr:blocked", payload: { active: false } });
});

test("withHerdrBlocked still unblocks when the run throws", async () => {
  const { pi, emitted } = fakePi();
  let threw = false;
  try {
    await withHerdrBlocked(pi, "Advance to Build?", async () => {
      throw new Error("dialog blew up");
    });
  } catch {
    threw = true;
  }
  assertEqual(threw, true, "the error propagates");
  assertEqual(emitted.length, 2, "the block is still balanced on throw");
  assertEqual(emitted[1], { event: "herdr:blocked", payload: { active: false } });
});
