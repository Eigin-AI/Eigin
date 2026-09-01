/**
 * Unit tests for the local `role:` model-resolution diff on top of the
 * vendored agent discovery logic.
 */

import { applySessionModel, resolveAgentModel } from "./model-role.ts";

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
	if (actual !== expected) {
		throw new Error(`${message || "Assertion failed"}\nExpected: ${expected}\nActual: ${actual}`);
	}
}

test("resolves a role: sentinel to the default model when no override is saved", () => {
	assertEqual(resolveAgentModel("role:explorer", {}), "anthropic/claude-haiku-4-5");
});

test("resolves a role: sentinel to a saved override", () => {
	const overrides = { explorer: { provider: "openai", id: "gpt-5-mini" } };
	assertEqual(resolveAgentModel("role:explorer", overrides), "openai/gpt-5-mini");
});

test("passes through a literal model id unchanged", () => {
	assertEqual(resolveAgentModel("claude-haiku-4-5", {}), "claude-haiku-4-5");
});

test("passes through undefined unchanged", () => {
	assertEqual(resolveAgentModel(undefined, {}), undefined);
});

test("degrades to undefined for an unknown role name rather than crashing", () => {
	assertEqual(resolveAgentModel("role:nonexistent", {}), undefined);
});

test("resolves each real role name", () => {
	assertEqual(resolveAgentModel("role:planner", {}), "anthropic/claude-opus-4-8");
	assertEqual(resolveAgentModel("role:builder", {}), "anthropic/claude-sonnet-5");
	assertEqual(resolveAgentModel("role:explorer", {}), "anthropic/claude-haiku-4-5");
});

const session = { provider: "berget", id: "zai-org/GLM-5.3" };

test("an agent with no model of its own runs on the session's model", () => {
	const [agent] = applySessionModel([{ name: "reviewer" }], session);
	assertEqual(agent.model, "berget/zai-org/GLM-5.3");
});

test("an agent that pins a model keeps it", () => {
	const [agent] = applySessionModel([{ name: "explore", model: "anthropic/claude-haiku-4-5" }], session);
	assertEqual(agent.model, "anthropic/claude-haiku-4-5");
});

test("agents are left alone when there is no session model", () => {
	const agents = [{ name: "reviewer" }];
	assertEqual(applySessionModel(agents, undefined), agents);
});

console.log("\nAll model-role tests completed.");
