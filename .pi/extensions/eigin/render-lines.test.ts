/**
 * Unit tests for render-line sanitizing (pure, no IO).
 *
 * The compact tool renderer in `tool-rendering.ts` builds raw lines that
 * `linesComponent` truncates to terminal width. pi-tui assumes every returned
 * array entry is exactly one physical terminal row and counts control
 * characters as zero-width — so an embedded newline must be split before the
 * line reaches the TUI, or one logical "line" renders as several rows and the
 * cursor/scroll arithmetic drifts (duplicated tool blocks).
 */

import { collapseMultiline, toRenderLines } from "./render-lines.ts";

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
	const a = JSON.stringify(actual);
	const e = JSON.stringify(expected);
	if (a !== e) throw new Error(`${message || "Assertion failed"}\nExpected: ${e}\nActual: ${a}`);
}

test("splits embedded newlines into one row per line", () => {
	const command = `git commit -m "fix(ios): title (#259)\n\n- OnboardingScaffold: pinned; content scrolls"`;
	assertEqual(toRenderLines(command), [
		`git commit -m "fix(ios): title (#259)`,
		`- OnboardingScaffold: pinned; content scrolls"`,
	]);
});

test("normalizes CRLF and lone CR to newlines", () => {
	assertEqual(toRenderLines("a\r\nb\rc"), ["a", "b", "c"]);
});

test("strips other control characters that move the terminal cursor", () => {
	assertEqual(toRenderLines("a\x00\x07\x08\x0b\x7f b"), ["a b"]);
});

test("preserves ANSI escape sequences — theme styling stays intact", () => {
	const styled = "\x1b[38;2;212;212;212m$ \x1b[39mecho\x1b[38;2;138;190;183m hi\x1b[39m";
	assertEqual(toRenderLines(styled), [styled]);
});

test("expands tabs to three spaces like the built-in Text component", () => {
	assertEqual(toRenderLines("a\tb"), ["a   b"]);
});

test("drops empty lines so collapsed rows cost no height", () => {
	assertEqual(toRenderLines("a\n\n\nb\n"), ["a", "b"]);
});

test("never leaves a newline or carriage return inside a row", () => {
	const rows = toRenderLines("x\ny\r\nz\rw\ta");
	for (const row of rows) {
		if (/[\n\r]/.test(row)) throw new Error(`row contains a line break: ${JSON.stringify(row)}`);
	}
});

test("collapseMultiline keeps the first line and counts the rest", () => {
	assertEqual(collapseMultiline("one\ntwo\n\nthree"), { first: "one", rest: 2 });
	assertEqual(collapseMultiline("single"), { first: "single", rest: 0 });
	assertEqual(collapseMultiline(""), { first: "", rest: 0 });
});

console.log("\nAll render-lines tests completed.");
