/**
 * Unit tests for ask_questions validation.
 */

import { validateQuestions, type QuestionInput } from "./validation.ts";

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
		throw new Error(
			`${message || "Assertion failed"}\nExpected: ${expectedJson}\nActual: ${actualJson}`,
		);
	}
}

// Valid cases
test("accepts 2 questions with 2 options each", () => {
	const questions: QuestionInput[] = [
		{
			question: "First question?",
			options: [{ title: "Option A" }, { title: "Option B" }],
		},
		{
			question: "Second question?",
			options: [{ title: "Option 1" }, { title: "Option 2" }],
		},
	];
	const result = validateQuestions(questions);
	assertEqual(result, undefined, "Should be valid");
});

test("accepts 3 questions with 3 options each", () => {
	const questions: QuestionInput[] = [
		{
			question: "Q1?",
			options: [{ title: "A" }, { title: "B" }, { title: "C" }],
		},
		{
			question: "Q2?",
			options: [{ title: "1" }, { title: "2" }, { title: "3" }],
		},
		{
			question: "Q3?",
			options: [{ title: "X" }, { title: "Y" }, { title: "Z" }],
		},
	];
	const result = validateQuestions(questions);
	assertEqual(result, undefined, "Should be valid");
});

test("accepts 2 questions with mixed option counts (2 and 3)", () => {
	const questions: QuestionInput[] = [
		{
			question: "Q1?",
			options: [{ title: "A" }, { title: "B" }],
		},
		{
			question: "Q2?",
			options: [{ title: "1" }, { title: "2" }, { title: "3" }],
		},
	];
	const result = validateQuestions(questions);
	assertEqual(result, undefined, "Should be valid");
});

test("accepts options with descriptions", () => {
	const questions: QuestionInput[] = [
		{
			question: "Pick a color?",
			options: [
				{ title: "Blue", description: "Calm and professional" },
				{ title: "Red", description: "Bold and urgent" },
			],
		},
		{
			question: "Pick a shape?",
			options: [{ title: "Circle" }, { title: "Square" }],
		},
	];
	const result = validateQuestions(questions);
	assertEqual(result, undefined, "Should be valid");
});

// Invalid cases: question count
test("rejects 1 question", () => {
	const questions: QuestionInput[] = [
		{
			question: "Only one?",
			options: [{ title: "A" }, { title: "B" }],
		},
	];
	const result = validateQuestions(questions);
	assertEqual(
		result !== undefined,
		true,
		"Should fail with 1 question",
	);
	assertEqual(
		result?.reason.includes("2–3 questions"),
		true,
		"Error message should mention range",
	);
});

test("rejects 4 questions", () => {
	const questions: QuestionInput[] = [
		{ question: "Q1?", options: [{ title: "A" }, { title: "B" }] },
		{ question: "Q2?", options: [{ title: "A" }, { title: "B" }] },
		{ question: "Q3?", options: [{ title: "A" }, { title: "B" }] },
		{ question: "Q4?", options: [{ title: "A" }, { title: "B" }] },
	];
	const result = validateQuestions(questions);
	assertEqual(
		result !== undefined,
		true,
		"Should fail with 4 questions",
	);
	assertEqual(
		result?.reason.includes("2–3 questions"),
		true,
		"Error message should mention range",
	);
});

test("rejects 0 questions", () => {
	const questions: QuestionInput[] = [];
	const result = validateQuestions(questions);
	assertEqual(
		result !== undefined,
		true,
		"Should fail with 0 questions",
	);
});

// Invalid cases: option count
test("rejects a question with 1 option", () => {
	const questions: QuestionInput[] = [
		{
			question: "Q1?",
			options: [{ title: "Only one" }],
		},
		{
			question: "Q2?",
			options: [{ title: "A" }, { title: "B" }],
		},
	];
	const result = validateQuestions(questions);
	assertEqual(
		result !== undefined,
		true,
		"Should fail with 1 option",
	);
	assertEqual(
		result?.reason.includes("2–3"),
		true,
		"Error message should mention option range",
	);
});

test("rejects a question with 4 options", () => {
	const questions: QuestionInput[] = [
		{
			question: "Q1?",
			options: [{ title: "A" }, { title: "B" }],
		},
		{
			question: "Too many?",
			options: [
				{ title: "A" },
				{ title: "B" },
				{ title: "C" },
				{ title: "D" },
			],
		},
	];
	const result = validateQuestions(questions);
	assertEqual(
		result !== undefined,
		true,
		"Should fail with 4 options",
	);
	assertEqual(
		result?.reason.includes("2–3"),
		true,
		"Error message should mention option range",
	);
});

test("rejects a question with 0 options", () => {
	const questions: QuestionInput[] = [
		{
			question: "Q1?",
			options: [],
		},
		{
			question: "Q2?",
			options: [{ title: "A" }, { title: "B" }],
		},
	];
	const result = validateQuestions(questions);
	assertEqual(
		result !== undefined,
		true,
		"Should fail with 0 options",
	);
});

// Invalid cases: empty strings
test("rejects empty question text", () => {
	const questions: QuestionInput[] = [
		{
			question: "",
			options: [{ title: "A" }, { title: "B" }],
		},
		{
			question: "Q2?",
			options: [{ title: "A" }, { title: "B" }],
		},
	];
	const result = validateQuestions(questions);
	assertEqual(
		result !== undefined,
		true,
		"Should fail with empty question text",
	);
	assertEqual(
		result?.reason.includes("empty text"),
		true,
		"Error message should mention empty text",
	);
});

test("rejects whitespace-only question text", () => {
	const questions: QuestionInput[] = [
		{
			question: "   ",
			options: [{ title: "A" }, { title: "B" }],
		},
		{
			question: "Q2?",
			options: [{ title: "A" }, { title: "B" }],
		},
	];
	const result = validateQuestions(questions);
	assertEqual(
		result !== undefined,
		true,
		"Should fail with whitespace-only question text",
	);
});

test("rejects empty option title", () => {
	const questions: QuestionInput[] = [
		{
			question: "Q1?",
			options: [{ title: "" }, { title: "B" }],
		},
		{
			question: "Q2?",
			options: [{ title: "A" }, { title: "B" }],
		},
	];
	const result = validateQuestions(questions);
	assertEqual(
		result !== undefined,
		true,
		"Should fail with empty option title",
	);
	assertEqual(
		result?.reason.includes("empty"),
		true,
		"Error message should mention empty",
	);
});

test("rejects whitespace-only option title", () => {
	const questions: QuestionInput[] = [
		{
			question: "Q1?",
			options: [{ title: "A" }, { title: "  " }],
		},
		{
			question: "Q2?",
			options: [{ title: "A" }, { title: "B" }],
		},
	];
	const result = validateQuestions(questions);
	assertEqual(
		result !== undefined,
		true,
		"Should fail with whitespace-only option title",
	);
});

console.log("\nAll validation tests completed.");
