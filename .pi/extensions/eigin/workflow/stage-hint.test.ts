/**
 * Unit tests for the per-turn stage hint (context-event injection).
 */

import { appendStageHintIfFreshTurn, buildStageHint, type StageHintMessage } from "./stage-hint.ts";

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

test("buildStageHint includes the stage label and guidance", () => {
	const hint = buildStageHint("Plan", "Narrow the funnel.");
	if (!hint.includes("Plan") || !hint.includes("Narrow the funnel.")) {
		throw new Error(`Hint missing expected content: ${hint}`);
	}
});

test("appends hint to a fresh user message with string content", () => {
	const messages: StageHintMessage[] = [{ role: "user", content: "Hello" }];
	const result = appendStageHintIfFreshTurn(messages, "HINT");

	assertEqual(result.length, 1);
	assertEqual(result[0].role, "user");
	assertEqual(result[0].content, [
		{ type: "text", text: "Hello" },
		{ type: "text", text: "HINT" },
	]);
});

test("appends hint to a fresh user message with array content", () => {
	const messages: StageHintMessage[] = [
		{ role: "user", content: [{ type: "text", text: "Hello" }, { type: "image", data: "x", mimeType: "image/png" }] },
	];
	const result = appendStageHintIfFreshTurn(messages, "HINT");

	assertEqual(result[0].content, [
		{ type: "text", text: "Hello" },
		{ type: "image", data: "x", mimeType: "image/png" },
		{ type: "text", text: "HINT" },
	]);
});

test("does not modify when the last message is not a user message", () => {
	const messages: StageHintMessage[] = [
		{ role: "user", content: "Hello" },
		{ role: "assistant", content: [{ type: "text", text: "Hi" }] },
	];
	const result = appendStageHintIfFreshTurn(messages, "HINT");
	assertEqual(result, messages);
});

test("does not modify when the last message is a tool result (mid-turn continuation)", () => {
	const messages: StageHintMessage[] = [
		{ role: "user", content: "Hello" },
		{ role: "assistant", content: [{ type: "toolCall", id: "1" }] },
		{ role: "toolResult", content: [{ type: "text", text: "result" }] },
	];
	const result = appendStageHintIfFreshTurn(messages, "HINT");
	assertEqual(result, messages);
});

test("returns an empty array unchanged", () => {
	const result = appendStageHintIfFreshTurn([], "HINT");
	assertEqual(result, []);
});

test("does not mutate the input array or its messages", () => {
	const original: StageHintMessage[] = [{ role: "user", content: "Hello" }];
	const originalCopy = JSON.parse(JSON.stringify(original));
	appendStageHintIfFreshTurn(original, "HINT");
	assertEqual(original, originalCopy);
});

console.log("\nAll stage-hint tests completed.");
