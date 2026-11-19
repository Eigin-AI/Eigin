import { test } from "node:test";
import assert from "node:assert/strict";
import { foldoutParts } from "../src/lib/foldouts.ts";

test("only explicitly fenced headings become disclosures, independent of their wording", () => {
  const parts = foldoutParts(
    "## Outside\n\nOrdinary copy.\n\n<!-- foldouts -->\n\n### Arbitrary item\n\nBody.\n\n#### Nested heading\n\nNested copy.\n\n### Another item\n\nMore.\n\n<!-- end-foldouts -->\n\n### Outside again",
  );
  assert.equal(parts.length, 3);
  assert.equal(parts[1].kind, "foldouts");
  if (parts[1].kind !== "foldouts") throw new Error("Expected disclosures");
  assert.deepEqual(
    parts[1].items.map((item) => item.title),
    ["Arbitrary item", "Another item"],
  );
  assert.match(parts[1].items[0].body, /#### Nested heading/);
  assert.equal(parts[2].kind, "copy");
});
test("ordinary headings, unclosed fences and code examples remain ordinary Markdown", () => {
  for (const text of [
    "## Constraints\n\n### Local-first",
    "<!-- foldouts -->\n\n## Unclosed",
    "```md\n<!-- foldouts -->\n\n## Code\n<!-- end-foldouts -->\n```",
  ]) {
    assert.ok(foldoutParts(text).every((part) => part.kind === "copy"));
  }
});
