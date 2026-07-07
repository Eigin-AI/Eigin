/**
 * Unit tests for the pure parsing logic in the /role command.
 */

import { parseModelSpec } from "./role-command.ts";

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

test("parses a bare model id with no provider", () => {
	assertEqual(parseModelSpec("claude-opus-4-8"), { id: "claude-opus-4-8" });
});

test("parses a provider/id spec", () => {
	assertEqual(parseModelSpec("anthropic/claude-opus-4-8"), { provider: "anthropic", id: "claude-opus-4-8" });
});

test("only splits on the first slash", () => {
	assertEqual(parseModelSpec("openrouter/anthropic/claude-opus"), {
		provider: "openrouter",
		id: "anthropic/claude-opus",
	});
});

console.log("\nAll role-command tests completed.");
