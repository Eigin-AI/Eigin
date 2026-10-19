/**
 * Unit tests for stretchtext rendering. Run: node render.test.ts
 */

import { parse } from "./parse.ts";
import { renderSegments, stretchtextStyle, superscript, type StretchStyle } from "./render.ts";

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
	if (JSON.stringify(actual) !== JSON.stringify(expected)) {
		throw new Error(
			`${message || "Assertion failed"}\nExpected: ${JSON.stringify(expected)}\nActual: ${JSON.stringify(actual)}`,
		);
	}
}

/** Readable stand-in for the themed style. */
const st: StretchStyle = {
	closed: (t) => `[${t}]`,
	added: (t) => `<${t}>`,
	marker: (t) => t,
	collapse: (t) => `/${t}/`,
};

const closed = new Set<string>();
const state = (open: ReadonlySet<string>, digits?: ReadonlyMap<string, number>) => ({
	open,
	digits,
	style: st,
});

test("closed stretch renders the short form styled, no digit without one", () => {
	const out = renderSegments(parse("The fix: {{clear the cache|clear the stale dependency cache}}."), state(closed));
	assertEqual(out, "The fix: [clear the cache].");
});

test("open stretch renders the long form with a collapse marker", () => {
	const out = renderSegments(parse("{{short|long form here}}"), state(new Set(["short"])));
	// Short word "short" is absent from the long form → fallback plain.
	assertEqual(out, "long form here /«/");
});

test("open stretch: short's words keep the closed style, new words take style.added", () => {
	const out = renderSegments(parse("{{the build fails|the build fails on a stale cache}}"), {
		open: new Set(["the build fails"]),
		style: st,
	});
	assertEqual(out, "[the build fails ]<on a stale cache> /«/");
});

test("anchor matching: short's words are anchors, only the rest is added", () => {
	const out = renderSegments(parse("{{clear the cache|clear the stale cache now}}"), state(new Set(["clear the cache"])));
	assertEqual(out, "[clear the ]<stale >[cache ]<now> /«/");
});

test("anchor matching strips punctuation, so 'color' matches 'color,':", () => {
	const out = renderSegments(parse("{{accent color|accent color, clearly different}}"), state(new Set(["accent color"])));
	assertEqual(out, "[accent color, ]<clearly different> /«/");
});

test("runs keep whitespace inside the style, so underlines persist through spaces", () => {
	// The expectations above carry inner spaces inside [ ] and < >; this test
	// just names the invariant explicitly via the themed style.
	const s = stretchtextStyle({ fg: (color, text) => `<${color}|${text}>` });
	const out = renderSegments(parse("{{a b|a b c d}}"), {
		open: new Set(["a b"]),
		style: s,
	});
	// Whole anchor run and whole added run each wrap one span.
	assertEqual(out, "\x1b[4m<accent|a b >\x1b[24m\x1b[4m<muted|c d>\x1b[24m <accent|«>");
});

test("anchor fallback: broken promise renders everything plain", () => {
	const out = renderSegments(parse("{{short|completely different words}}"), state(new Set(["short"])));
	assertEqual(out, "completely different words /«/");
});

test("digits render as superscripts on both states, riding the end when open", () => {
	const segs = parse("{{a|aaa}} {{b|bbb}}");
	const digits = new Map([
		["a", 1],
		["b", 2],
	]);
	assertEqual(renderSegments(segs, state(closed, digits)), "[a]¹ [b]²");
	assertEqual(renderSegments(segs, state(new Set(["a"]), digits)), "aaa /«/¹ [b]²");
});

test("nested stretch inside an open parent keeps its own state", () => {
	const segs = parse("{{a|x {{b|y}} z}}");
	assertEqual(renderSegments(segs, state(new Set(["a"]))), "x [b] z /«/");
	assertEqual(renderSegments(segs, state(new Set(["a", "a › b"]))), "x y /«/ z /«/");
});

test("streaming (unterminated) stretch renders its short form as plain text", () => {
	const out = renderSegments(parse("done {{short|long arriving"), state(closed));
	assertEqual(out, "done short");
});

test("pipe-less stretch renders as plain text", () => {
	const out = renderSegments(parse("a {{plain}} b"), state(closed));
	assertEqual(out, "a plain b");
});

test("whitespace around the short form stays outside the style", () => {
	const out = renderSegments(parse("{{ padded |long}}"), state(closed));
	assertEqual(out, " [padded] ");
});

test("superscript falls back to plain digits past 9", () => {
	assertEqual(superscript(3), "³");
	assertEqual(superscript(10), "10");
});

test("themed style: closed accent-underlined, added muted-underlined, whole span", () => {
	const s = stretchtextStyle({ fg: (color, text) => `<${color}>${text}</>` });
	assertEqual(s.closed("hi"), "\x1b[4m<accent>hi</>\x1b[24m");
	assertEqual(s.added("new"), "\x1b[4m<muted>new</>\x1b[24m");
	assertEqual(s.collapse("«"), "<accent>«</>");
	assertEqual(s.marker("3"), "<accent>3</>");
});

console.log("\nAll render tests completed.");
