/**
 * Unit tests for the review kickoff composition.
 */

import { reviewKickoff } from "./review-handoff.ts";

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

const base = {
	diffPath: ".pi/review/82-monitoring.diff",
	guidePath: ".pi/guidance/review-guide.md",
	planPath: ".pi/plans/82-monitoring.md",
	atMerge: true,
};

test("kickoff names the subagent, the agent, and every path", () => {
	const text = reviewKickoff(base);
	assert(text.includes("`subagent`"), "should name the subagent tool");
	assert(text.includes("`reviewer`"), "should name the reviewer agent");
	assert(text.includes(base.diffPath), "should name the diff path");
	assert(text.includes(base.guidePath), "should name the guide path");
	assert(text.includes(base.planPath), "should name the plan path");
});

test("kickoff omits the plan line when there is no plan", () => {
	const text = reviewKickoff({ ...base, planPath: null });
	assert(!text.includes("The plan:"), "should not mention a plan that doesn't exist");
	assert(text.includes(base.diffPath), "should still name the diff path");
});

test("kickoff runs two capped rounds", () => {
	const text = reviewKickoff(base);
	const rounds = [text.indexOf("Round 1"), text.indexOf("Round 2")];
	assert(rounds.every((r) => r >= 0), "should have both round headings");
	assert(rounds[0] < rounds[1], "round 1 must come before round 2");
	assert(/(exactly once|no third round)/.test(text), "the follow-up should be capped");
	assert(text.includes("git diff main"), "round 2 should refresh the diff");
});

test("round 2 sends the report and the response back to the reviewer", () => {
	const text = reviewKickoff(base);
	const round2 = text.slice(text.indexOf("Round 2"));
	assert(round2.includes("report"), "the round-1 report should go back");
	assert(round2.includes("response"), "the builder's response should go back");
	assert(round2.includes("pushback"), "pushback should return to the reviewer");
});

test("kickoff asks for the review before the MR", () => {
	const text = reviewKickoff(base);
	assert(text.indexOf("review") < text.indexOf("open the MR"), "review should come before opening the MR");
	assert(text.includes("tasks"), "findings should become tasks");
});

test("an on-demand review hands back instead of opening the MR", () => {
	const text = reviewKickoff({ ...base, atMerge: false });
	assert(!text.includes("open the MR"), "a check-in shouldn't drive the MR");
	assert(text.includes("hand back to the user"), "should hand back when done");
	assert(text.includes("`reviewer`"), "should still run the reviewer");
});
