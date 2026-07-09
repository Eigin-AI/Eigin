/**
 * Unit tests for observability/session-name.ts (plain node --experimental-strip-types, no framework).
 */

import { buildNamerPrompt, cleanSessionName, extractLastUserText } from "./session-name.ts";

function test(name: string, fn: () => void): void {
  try {
    fn();
    console.log(`✓ ${name}`);
  } catch (err) {
    console.error(`✗ ${name}`);
    console.error(err);
    process.exitCode = 1;
  }
}

function assertEqual<T>(actual: T, expected: T, message?: string): void {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`${message ?? "assertion failed"}: expected ${expectedJson}, got ${actualJson}`);
  }
}

test("cleanSessionName passes through a clean name unchanged", () => {
  assertEqual(cleanSessionName("Fix auth token refresh bug"), "Fix auth token refresh bug");
});

test("cleanSessionName strips a matching pair of double quotes", () => {
  assertEqual(cleanSessionName('"Fix auth token refresh bug"'), "Fix auth token refresh bug");
});

test("cleanSessionName strips a matching pair of single quotes", () => {
  assertEqual(cleanSessionName("'Fix login flow'"), "Fix login flow");
});

test("cleanSessionName takes only the first line", () => {
  assertEqual(cleanSessionName("Fix login flow\nExtra reasoning the model added anyway"), "Fix login flow");
});

test("cleanSessionName truncates long names with an ellipsis", () => {
  const raw = "This is a very long session name that should definitely be truncated for the title bar";
  const result = cleanSessionName(raw);
  if (!result) throw new Error("expected a name");
  if (result.length > 50) throw new Error(`expected length <= 50, got ${result.length}`);
  if (!result.endsWith("…")) throw new Error(`expected ellipsis, got "${result}"`);
});

test("cleanSessionName returns undefined for empty input", () => {
  assertEqual(cleanSessionName(""), undefined);
});

test("cleanSessionName returns undefined for whitespace-only input", () => {
  assertEqual(cleanSessionName("   \n  "), undefined);
});

test("buildNamerPrompt embeds the source text and asks for a short name", () => {
  const prompt = buildNamerPrompt("Fix the login bug");
  if (!prompt.includes("Fix the login bug")) throw new Error("prompt missing source text");
  if (!prompt.includes("50 characters")) throw new Error("prompt missing max length instruction");
});

test("extractLastUserText finds the most recent user message, scanning from the end", () => {
  const entries = [
    { type: "message", message: { role: "user", content: "First prompt" } },
    { type: "message", message: { role: "assistant", content: "reply" } },
    { type: "message", message: { role: "user", content: [{ type: "text", text: "Second prompt" }] } },
  ];
  assertEqual(extractLastUserText(entries), "Second prompt");
});

test("extractLastUserText skips non-message entries and empty user text", () => {
  const entries = [
    { type: "message", message: { role: "user", content: "Real prompt" } },
    { type: "message", message: { role: "user", content: "" } },
    { type: "custom", message: { role: "user", content: "not a message entry" } },
  ];
  assertEqual(extractLastUserText(entries), "Real prompt");
});

test("extractLastUserText returns undefined when there's no user message", () => {
  const entries = [{ type: "message", message: { role: "assistant", content: "hi" } }];
  assertEqual(extractLastUserText(entries), undefined);
});
