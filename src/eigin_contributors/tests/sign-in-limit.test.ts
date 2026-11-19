import { test } from "node:test";
import assert from "node:assert/strict";
import { signInLimit } from "../src/lib/server/sign-in-limit.ts";

test("limits starts per address and in aggregate, then resets", () => {
  let now = 0;
  const allow = signInLimit(() => now);
  for (let i = 0; i < 10; i++) assert.equal(allow("first"), 0);
  assert.equal(allow("first"), 60);
  for (let i = 0; i < 110; i++) assert.equal(allow(`other-${i}`), 0);
  assert.equal(allow("another"), 60);
  now = 59_500;
  assert.equal(allow("another"), 1);
  now = 60_000;
  assert.equal(allow("first"), 0);
  assert.equal(allow("another"), 0);
});
