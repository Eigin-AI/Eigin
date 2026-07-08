/**
 * Unit tests for the pure task-list state functions.
 */

import {
	addTasks,
	clearTasks,
	emptyTaskList,
	formatTaskList,
	resolveTasks,
	summarizeTaskList,
} from "./task-list.ts";

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

test("emptyTaskList starts with no tasks and id 1", () => {
	assertEqual(emptyTaskList(), { tasks: [], nextId: 1 });
});

test("addTasks assigns sequential ids and skips blanks", () => {
	const { state, added } = addTasks(emptyTaskList(), ["First", "  ", "Second"]);
	assertEqual(added, [
		{ id: 1, text: "First", done: false },
		{ id: 2, text: "Second", done: false },
	]);
	assertEqual(state.tasks, added);
	assertEqual(state.nextId, 3);
});

test("addTasks appends to existing state without mutating it", () => {
	const first = addTasks(emptyTaskList(), ["A"]).state;
	const { state } = addTasks(first, ["B"]);
	assertEqual(first.tasks, [{ id: 1, text: "A", done: false }]);
	assertEqual(state.tasks, [
		{ id: 1, text: "A", done: false },
		{ id: 2, text: "B", done: false },
	]);
});

test("resolveTasks marks matching ids done and reports missing ones", () => {
	const { state: withTasks } = addTasks(emptyTaskList(), ["A", "B", "C"]);
	const { state, resolved, missing } = resolveTasks(withTasks, [2, 99]);

	assertEqual(resolved, [2]);
	assertEqual(missing, [99]);
	assertEqual(state.tasks, [
		{ id: 1, text: "A", done: false },
		{ id: 2, text: "B", done: true },
		{ id: 3, text: "C", done: false },
	]);
});

test("resolveTasks keeps resolved tasks visible rather than removing them", () => {
	const { state: withTasks } = addTasks(emptyTaskList(), ["A"]);
	const { state } = resolveTasks(withTasks, [1]);
	assertEqual(state.tasks.length, 1);
	assertEqual(state.tasks[0].done, true);
});

test("formatTaskList returns null when empty", () => {
	assertEqual(formatTaskList(emptyTaskList()), null);
});

test("formatTaskList renders checkboxes for done and pending tasks", () => {
	const { state: withTasks } = addTasks(emptyTaskList(), ["A", "B"]);
	const { state } = resolveTasks(withTasks, [1]);
	assertEqual(formatTaskList(state), "Task list:\n[x] 1. A\n[ ] 2. B");
});

test("summarizeTaskList returns null when empty, else done/total", () => {
	assertEqual(summarizeTaskList(emptyTaskList()), null);
	const { state: withTasks } = addTasks(emptyTaskList(), ["A", "B", "C"]);
	const { state } = resolveTasks(withTasks, [1, 2]);
	assertEqual(summarizeTaskList(state), "✅ 2/3");
});

test("clearTasks removes every task but keeps the id counter moving forward", () => {
	const { state: withTasks } = addTasks(emptyTaskList(), ["A", "B"]);
	const cleared = clearTasks(withTasks);
	assertEqual(cleared.tasks, []);
	assertEqual(cleared.nextId, withTasks.nextId);
	assertEqual(formatTaskList(cleared), null);
});

console.log("\nAll task-list tests completed.");
