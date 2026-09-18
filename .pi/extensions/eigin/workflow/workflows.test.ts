/**
 * Unit tests for the workflow registry (pure state/config, no UI).
 */

import { STAGE_META } from "./stages.ts";
import {
	firstStage,
	getStageInWorkflow,
	getWorkflow,
	hasStage,
	isWorkflowId,
	relativeStageIn,
	stageIndexIn,
	WORKFLOWS,
} from "./workflows.ts";

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

function assert(condition: boolean, message: string): void {
	if (!condition) throw new Error(message);
}

test("WORKFLOWS has exactly feature, bug, prototype, release", () => {
	assertEqual(
		WORKFLOWS.map((w) => w.id),
		["feature", "bug", "prototype", "release"],
	);
});

test("every workflow's stages exist in STAGE_META", () => {
	for (const workflow of WORKFLOWS) {
		for (const s of workflow.stages) {
			assert(s.id in STAGE_META, `${workflow.id}: unknown stage id "${s.id}"`);
		}
	}
});

test("feature workflow is context → plan → build → merge (no review stage; iterate was dropped)", () => {
	assertEqual(
		getWorkflow("feature").stages.map((s) => s.id),
		["context", "plan", "build", "merge"],
	);
});

test("bug workflow drops the test stage", () => {
	const stages = getWorkflow("bug").stages.map((s) => s.id);
	assertEqual(stages, ["context", "plan", "build", "merge"]);
});

test("no workflow has a review stage (code review is on the MR in merge)", () => {
	for (const w of WORKFLOWS) {
		assert(!w.stages.some((s) => s.id === "review"), `${w.id} should not have a review stage`);
	}
});

test("prototype workflow skips plan", () => {
	assertEqual(
		getWorkflow("prototype").stages.map((s) => s.id),
		["context", "iterate", "merge"],
	);
});

test("release has the only test stage (a release bump is verified as its own step)", () => {
	assertEqual(
		getWorkflow("release").stages.map((s) => s.id),
		["context", "plan", "build", "test", "merge"],
	);
});

test("isWorkflowId recognizes valid/invalid ids", () => {
	assert(isWorkflowId("feature"), "feature should be a valid workflow id");
	assert(!isWorkflowId("nonsense"), "nonsense should not be a valid workflow id");
});

test("firstStage returns each workflow's entry stage", () => {
	assertEqual(firstStage(getWorkflow("feature")), "context");
	assertEqual(firstStage(getWorkflow("bug")), "context");
	assertEqual(firstStage(getWorkflow("prototype")), "context");
	assertEqual(firstStage(getWorkflow("release")), "context");
});

test("hasStage reflects workflow membership", () => {
	assert(!hasStage(getWorkflow("bug"), "test"), "bug workflow should not include test");
	assert(!hasStage(getWorkflow("feature"), "test"), "feature workflow should not include test");
	assert(!hasStage(getWorkflow("feature"), "review"), "feature workflow should not include review");
});

test("getStageInWorkflow returns the stage, throws for one outside the workflow", () => {
	assertEqual(getStageInWorkflow(getWorkflow("bug"), "context").label, "Context");

	let threw = false;
	try {
		getStageInWorkflow(getWorkflow("prototype"), "plan");
	} catch {
		threw = true;
	}
	assert(threw, "expected getStageInWorkflow to throw for a stage outside the workflow");
});

test("stageIndexIn finds position within a workflow's sequence", () => {
	assertEqual(stageIndexIn(getWorkflow("release"), "test"), 3);
	assertEqual(stageIndexIn(getWorkflow("bug"), "merge"), 3);
});

test("relativeStageIn steps forward/back and clamps at the bounds", () => {
	const bug = getWorkflow("bug");
	assertEqual(relativeStageIn(bug, "context", 1).id, "plan");
	assertEqual(relativeStageIn(bug, "merge", 1).id, "merge"); // Clamped at the end.
	assertEqual(relativeStageIn(bug, "context", -1).id, "context"); // Clamped at the start.
});

test("getWorkflow throws for an unknown id", () => {
	let threw = false;
	try {
		// @ts-expect-error deliberately invalid for the test
		getWorkflow("nonsense");
	} catch {
		threw = true;
	}
	assert(threw, "expected getWorkflow to throw for an unknown id");
});

console.log("\nAll workflow registry tests completed.");
