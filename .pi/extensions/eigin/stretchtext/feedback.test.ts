/**
 * Unit tests for the stretchtext feedback note. Run: node feedback.test.ts
 */

import { buildFeedbackNote } from "./feedback.ts";

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

function assert(cond: boolean, message: string): void {
	if (!cond) throw new Error(message);
}

test("lists opened and unopened stretches", () => {
	const note = buildFeedbackNote([
		{ short: "the fix ", opened: true },
		{ short: "the cause", opened: false },
	])!;
	assert(note.includes('opened "the fix"'), `opened quoted+trimmed: ${note}`);
	assert(note.includes('did not open "the cause"'), `unopened listed: ${note}`);
	assert(note.includes("Automatically injected"), `injection marker: ${note}`);
});

test("omits the unopened clause when everything was opened", () => {
	const note = buildFeedbackNote([{ short: "a", opened: true }])!;
	assert(note.includes('opened "a"'), `opened: ${note}`);
	assert(!note.includes("did not open"), `no unopened clause: ${note}`);
});

test("says so when nothing was opened", () => {
	const note = buildFeedbackNote([{ short: "a", opened: false }])!;
	assert(note.includes("opened none of the stretches"), `none opened: ${note}`);
});

test("returns null when the reply had no stretches", () => {
	assert(buildFeedbackNote([]) === null, "null for no stretches");
});

console.log("\nAll feedback tests completed.");
