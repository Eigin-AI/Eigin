/**
 * Unit tests for plan_review's decision → guidance contract.
 */

import { formatDecision, toPlanReviewResult } from "./plan-review-message.ts";

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

function assertIncludes(haystack: string, ...needles: string[]): void {
	for (const needle of needles) {
		assert(haystack.includes(needle), `expected "${haystack}" to include "${needle}"`);
	}
}

test("plain approval points at the propose_stage gate", () => {
	const text = formatDecision({ approved: true });
	assertIncludes(text, "APPROVED", "Decision log", "propose_stage(build)");
});

test("approval with notes frames notes as guidance, not rework", () => {
	const text = formatDecision({ approved: true, feedback: "  prefer Redis  " });
	assertIncludes(text, "APPROVED with notes", "guidance", "prefer Redis", "propose_stage(build)");
});

test("requested changes point back at plan_review resubmission", () => {
	const text = formatDecision({ approved: false, feedback: "too vague" });
	assertIncludes(text, "requested changes", "too vague", "plan_review again", "Decision log");
});

test("requested changes without feedback still renders a call to action", () => {
	const text = formatDecision({ approved: false });
	assertIncludes(text, "requested changes", "(none)");
});

test("closed-without-decision falls back to co-editing", () => {
	const result = toPlanReviewResult({ approved: false });
	assert(result.kind === "closed-without-decision", `unexpected kind ${result.kind}`);
	assertIncludes(result.message, "wait_for_user");
});

test("decisions pass through with their feedback", () => {
	const approved = toPlanReviewResult({ approved: true, feedback: "notes here" });
	assert(approved.kind === "decision", `unexpected kind ${approved.kind}`);
	assert(approved.decision?.approved === true);
	assert(approved.decision?.feedback === "notes here");

	const denied = toPlanReviewResult({ approved: false, feedback: "fix this" });
	assert(denied.kind === "decision", `unexpected kind ${denied.kind}`);
	assert(denied.decision?.approved === false);
});

console.log("\nplan-review tests completed.");
