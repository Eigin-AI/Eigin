/**
 * Unit tests for AFK mode state (pure, no IO).
 */

import { emptyAfk, isAfk, setAfk, toggleAfk } from "./afk-mode.ts";

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
	const a = JSON.stringify(actual);
	const e = JSON.stringify(expected);
	if (a !== e) throw new Error(`${message || "Assertion failed"}\nExpected: ${e}\nActual: ${a}`);
}

test("emptyAfk starts disabled", () => {
	assertEqual(emptyAfk(), { enabled: false });
	assert(!isAfk(emptyAfk()), "empty state should not be AFK");
});

test("setAfk(true) enables AFK", () => {
	const s = setAfk(true);
	assertEqual(s, { enabled: true });
	assert(isAfk(s), "setAfk(true) should be AFK");
});

test("setAfk(false) from an enabled state disables AFK", () => {
	const enabled = setAfk(true);
	const disabled = setAfk(false);
	assert(!isAfk(disabled), "setAfk(false) should not be AFK");
	// setAfk is absolute — prior state is irrelevant.
	assertEqual(setAfk(false), disabled);
});

test("toggleAfk flips the current state", () => {
	assert(isAfk(toggleAfk(emptyAfk())), "toggle off→on");
	assert(!isAfk(toggleAfk(setAfk(true))), "toggle on→off");
});

test("setAfk and toggleAfk return new values, not mutate", () => {
	const original = emptyAfk();
	setAfk(true);
	toggleAfk(original);
	assertEqual(original, { enabled: false }, "original must be unchanged");
});

function assert(condition: boolean, message: string): void {
	if (!condition) throw new Error(message);
}

console.log("\nAFK mode tests completed.");
