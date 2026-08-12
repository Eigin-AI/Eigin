/**
 * Unit tests for active-plan tracking (pure state, no IO).
 */

import {
	changedSinceSeen,
	diffSinceSeen,
	lineDiff,
	markSeen,
	noActivePlan,
	setActivePlan,
} from "./active-plan.ts";

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

function assert(condition: boolean, message: string): void {
	if (!condition) throw new Error(message);
}

function assertEqual<T>(actual: T, expected: T, message?: string): void {
	const a = JSON.stringify(actual);
	const e = JSON.stringify(expected);
	if (a !== e) throw new Error(`${message || "Assertion failed"}\nExpected: ${e}\nActual: ${a}`);
}

test("noActivePlan starts empty", () => {
	assertEqual(noActivePlan(), { path: null, lastSeenContent: null });
});

test("setActivePlan sets the path and leaves content unseen", () => {
	const s = setActivePlan(noActivePlan(), ".pi/plans/x.md");
	assertEqual(s, { path: ".pi/plans/x.md", lastSeenContent: null });
});

test("setActivePlan to the same path is a no-op (keeps last-seen)", () => {
	const seen = markSeen(setActivePlan(noActivePlan(), ".pi/plans/x.md"), "hello");
	const again = setActivePlan(seen, ".pi/plans/x.md");
	assert(again.lastSeenContent === "hello", "same path should preserve last-seen content");
});

test("setActivePlan to a new path clears last-seen", () => {
	const seen = markSeen(setActivePlan(noActivePlan(), ".pi/plans/x.md"), "hello");
	const switched = setActivePlan(seen, ".pi/plans/y.md");
	assertEqual(switched, { path: ".pi/plans/y.md", lastSeenContent: null });
});

test("changedSinceSeen is false before anything is seen", () => {
	const s = setActivePlan(noActivePlan(), ".pi/plans/x.md");
	assert(!changedSinceSeen(s, "anything"), "nothing seen yet → not 'changed'");
});

test("changedSinceSeen reflects content difference", () => {
	const s = markSeen(setActivePlan(noActivePlan(), ".pi/plans/x.md"), "a\nb");
	assert(!changedSinceSeen(s, "a\nb"), "identical content is not changed");
	assert(changedSinceSeen(s, "a\nc"), "different content is changed");
});

test("diffSinceSeen is null before first sight and when unchanged", () => {
	const fresh = setActivePlan(noActivePlan(), ".pi/plans/x.md");
	assert(diffSinceSeen(fresh, "a") === null, "no diff before first sight");
	const seen = markSeen(fresh, "a\nb");
	assert(diffSinceSeen(seen, "a\nb") === null, "no diff when unchanged");
});

test("diffSinceSeen surfaces added and removed lines", () => {
	const seen = markSeen(setActivePlan(noActivePlan(), ".pi/plans/x.md"), "a\nb\nc");
	const diff = diffSinceSeen(seen, "a\nB\nc");
	assertEqual(diff, "- b\n+ B", "should show the changed line as remove+add");
});

test("lineDiff keeps unchanged context out and shows only edits", () => {
	assertEqual(lineDiff("a\nb\nc", "a\nb\nc\nd"), "+ d");
	assertEqual(lineDiff("a\nb", "a"), "- b");
	assertEqual(lineDiff("x", "x"), "");
});

console.log("\nAll active-plan tests completed.");
