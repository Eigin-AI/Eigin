/**
 * Unit tests for project-scoped tool defaults.
 */

import { applySubagentDefaults, applyWebSearchDefault, type ToolCallInput } from "./tool-defaults.ts";

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

test("sets workflow to auto-summary when web_search has no workflow", () => {
	const input: ToolCallInput = { query: "burgers" };
	applyWebSearchDefault("web_search", input);
	assertEqual(input.workflow, "auto-summary");
});

test("does not override an explicit workflow", () => {
	const input: ToolCallInput = { query: "burgers", workflow: "summary-review" };
	applyWebSearchDefault("web_search", input);
	assertEqual(input.workflow, "summary-review");
});

test("does not override an explicit 'none' workflow", () => {
	const input: ToolCallInput = { query: "burgers", workflow: "none" };
	applyWebSearchDefault("web_search", input);
	assertEqual(input.workflow, "none");
});

test("does not touch other tools", () => {
	const input: ToolCallInput = { path: "foo.ts" };
	applyWebSearchDefault("read", input);
	assertEqual(input.workflow, undefined);
});

test("sets agentScope and confirmProjectAgents defaults for subagent", () => {
	const input: ToolCallInput = { agent: "explore", task: "find the auth code" };
	applySubagentDefaults("subagent", input);
	assertEqual(input.agentScope, "both");
	assertEqual(input.confirmProjectAgents, false);
});

test("does not override an explicit agentScope or confirmProjectAgents", () => {
	const input: ToolCallInput = { agent: "explore", task: "...", agentScope: "user", confirmProjectAgents: true };
	applySubagentDefaults("subagent", input);
	assertEqual(input.agentScope, "user");
	assertEqual(input.confirmProjectAgents, true);
});

test("does not touch other tools for subagent defaults", () => {
	const input: ToolCallInput = { path: "foo.ts" };
	applySubagentDefaults("read", input);
	assertEqual(input.agentScope, undefined);
	assertEqual(input.confirmProjectAgents, undefined);
});

console.log("\nAll tool-defaults tests completed.");
