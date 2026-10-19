/**
 * Unit tests for the stretchtext markup parser. Run: node parse.test.ts
 */

import { collectOpenable, isCode, isOpenable, isStretch, parse, type Stretch } from "./parse.ts";

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
		throw new Error(`${message || "Assertion failed"}\nExpected: ${expectedJson}\nActual: ${actualJson}`);
	}
}

function stretchAt(segments: ReturnType<typeof parse>, index: number): Stretch {
	const seg = segments[index];
	if (!isStretch(seg)) throw new Error(`segment ${index} is not a stretch`);
	return seg;
}

test("parses a simple stretch", () => {
	const segs = parse("before {{short|long}} after");
	assertEqual(segs.length, 3);
	assertEqual(segs[0], "before ");
	assertEqual(segs[2], " after");
	const s = stretchAt(segs, 1);
	assertEqual(s.short, "short");
	assertEqual(s.long, ["long"]);
	assertEqual(s.terminated, true);
	assertEqual(s.key, "short");
});

test("nests stretches inside long forms", () => {
	const segs = parse("{{a|x {{b|y}} z}}");
	const outer = stretchAt(segs, 0);
	assertEqual(outer.short, "a");
	assertEqual(outer.long!.length, 3);
	const inner = stretchAt(outer.long!, 1);
	assertEqual(inner.short, "b");
	assertEqual(inner.key, "a › b");
	assertEqual(isOpenable(inner), true);
});

test("no nesting inside a short form", () => {
	// `{{` inside a short form is literal, so the first `}}` terminates the
	// stretch (cc-stretch semantics): short "a {{b", rest is literal text.
	const segs = parse("{{a {{b}} c|long}}");
	const s = stretchAt(segs, 0);
	assertEqual(s.short, "a {{b");
	assertEqual(s.long, undefined);
	assertEqual(segs[1], " c|long}}");
});

test("pipe-less stretch is plain text, not openable", () => {
	const segs = parse("{{just text}}");
	const s = stretchAt(segs, 0);
	assertEqual(s.short, "just text");
	assertEqual(s.long, undefined);
	assertEqual(isOpenable(s), false);
});

test("braces inside code spans are not markup", () => {
	const segs = parse("use `{{not|a stretch}}` here");
	// Code spans are their own segment; adjacent text no longer merges.
	assertEqual(isCode(segs[1]) && segs[1].text, "`{{not|a stretch}}`");
	assertEqual(segs[0], "use ");
	assertEqual(segs[2], " here");
	assertEqual(hasNoStretch(segs), true);
});

test("braces inside fenced code blocks are not markup", () => {
	const segs = parse("intro\n```\n{{not|a stretch}}\n```\noutro");
	assertEqual(hasNoStretch(segs), true);
	// Adjacent text merges into one segment.
	assertEqual(segs, ["intro\n```\n{{not|a stretch}}\n```\noutro"]);
});

function hasNoStretch(segs: ReturnType<typeof parse>): boolean {
	return !segs.some(isStretch);
}

test("unterminated stretch keeps partial state for streaming", () => {
	const segs = parse("{{short|long still arriving");
	const s = stretchAt(segs, 0);
	assertEqual(s.short, "short");
	assertEqual(s.long, ["long still arriving"]);
	assertEqual(s.terminated, false);
	assertEqual(isOpenable(s), false);
});

test("multi-line short form is not openable", () => {
	const segs = parse("{{line one\nline two|long}}");
	const s = stretchAt(segs, 0);
	assertEqual(isOpenable(s), false);
});

test("duplicate sibling short forms get deduped keys", () => {
	const segs = parse("{{same|one}} and {{same|two}}");
	assertEqual(stretchAt(segs, 0).key, "same");
	assertEqual(stretchAt(segs, 2).key, "same~2");
});

test("collectOpenable is pre-order and skips non-openable", () => {
	const segs = parse("{{a|x {{b|y}}}}{{plain}}{{multi\nline|z}}");
	const keys = collectOpenable(segs).map((s) => s.key);
	assertEqual(keys, ["a", "a › b"]);
});

test("stray pipes and braces outside stretches are literal", () => {
	const segs = parse("a | b }} c");
	assertEqual(segs, ["a | b }} c"]);
});

console.log("\nAll parse tests completed.");
