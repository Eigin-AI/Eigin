/**
 * Unit tests for the Plan→Build handoff composers.
 */

import { buildCompactionInstructions, buildKickoff } from "./build-handoff.ts";

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

test("buildCompactionInstructions includes the plan path when known", () => {
	const text = buildCompactionInstructions(".pi/plans/foo.md");
	assert(text.includes(".pi/plans/foo.md"), "should mention the plan path");
	assert(text.includes("why"), "should steer toward rationale, not a blow-by-blow");
});

test("buildCompactionInstructions omits the path cleanly when null", () => {
	const text = buildCompactionInstructions(null);
	assert(!text.includes("approved plan is saved"), "should not reference a path");
	assert(text.includes("Context and Plan"), "should still describe the summarization goal");
});

test("buildKickoff inlines the plan and path when both are known", () => {
	const text = buildKickoff(".pi/plans/foo.md", "# Foo\n\nDo the thing.");
	assert(text.includes(".pi/plans/foo.md"), "should mention the plan path");
	assert(text.includes("Do the thing."), "should inline the plan content");
	assert(text.trim().endsWith("Proceed."), "should end with Proceed.");
});

test("buildKickoff falls back cleanly with no plan tracked", () => {
	const text = buildKickoff(null, null);
	assert(!text.includes(".md"), "should not reference a path");
	assert(text.includes("Implement what we agreed above"), "should use the fallback text");
	assert(text.trim().endsWith("Proceed."), "should end with Proceed.");
});

test("buildKickoff falls back when path is known but content couldn't be read", () => {
	const text = buildKickoff(".pi/plans/foo.md", null);
	assert(text.includes("Implement what we agreed above"), "should use the fallback text when content is missing");
});

console.log("\nAll build-handoff tests completed.");
