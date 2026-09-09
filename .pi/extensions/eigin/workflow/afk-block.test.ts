/**
 * Unit tests for the AFK fallback keyword check (pure, no guardrails, no IO).
 *
 * `afkBlockedCommand` is integration-level (loads guardrails' real config under
 * `.pi/npm`); the fallback is the one pure unit here, exercised directly.
 */

import { fallbackBlocked } from "./afk-block.ts";

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

test("blocks a command containing a dangerous keyword", () => {
	assertEqual(
		fallbackBlocked("rm -rf /tmp/x"),
		{ reason: 'matches builtin-dangerous pattern "rm -rf" (fallback)' },
	);
});

test("blocks sudo anywhere in the command", () => {
	assertEqual(
		fallbackBlocked("make && sudo systemctl restart foo"),
		{ reason: 'matches builtin-dangerous pattern "sudo" (fallback)' },
	);
});

test("allows a safe command", () => {
	if (fallbackBlocked("echo hello") !== null) throw new Error("echo should be allowed");
	if (fallbackBlocked("git status") !== null) throw new Error("git status should be allowed");
	if (fallbackBlocked("ls -la") !== null) throw new Error("ls should be allowed");
});

test("plain rm without -rf is allowed", () => {
	if (fallbackBlocked("rm file.txt") !== null) throw new Error("plain rm should be allowed");
});

test("empty command is allowed", () => {
	if (fallbackBlocked("") !== null) throw new Error("empty command should be allowed");
});

console.log("\nAFK fallback tests completed.");
