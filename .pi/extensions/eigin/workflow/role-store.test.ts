/**
 * Unit tests for role override persistence. Uses real temp files (fs is
 * fast and reliable — no need to fake it), not the real `.pi/model-roles.json`.
 */

import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadRoleOverrides, resolveRoleModel, saveRoleOverride } from "./role-store.ts";
import { ROLE_DEFAULTS } from "./roles.ts";

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

function withTempDir(fn: (path: string) => void): void {
	const dir = mkdtempSync(join(tmpdir(), "eigin-role-store-"));
	try {
		fn(join(dir, "model-roles.json"));
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

test("loadRoleOverrides returns empty when the file doesn't exist", () => {
	withTempDir((path) => {
		assertEqual(loadRoleOverrides(path), {});
	});
});

test("resolveRoleModel falls back to the built-in default with no overrides", () => {
	assertEqual(resolveRoleModel("planner", {}), ROLE_DEFAULTS.planner);
	assertEqual(resolveRoleModel("builder", {}), ROLE_DEFAULTS.builder);
	assertEqual(resolveRoleModel("explorer", {}), ROLE_DEFAULTS.explorer);
});

test("saveRoleOverride then loadRoleOverrides round-trips", () => {
	withTempDir((path) => {
		saveRoleOverride("planner", { provider: "openai", id: "gpt-5" }, path);
		assertEqual(loadRoleOverrides(path), { planner: { provider: "openai", id: "gpt-5" } });
	});
});

test("saveRoleOverride preserves previously saved roles", () => {
	withTempDir((path) => {
		saveRoleOverride("planner", { provider: "openai", id: "gpt-5" }, path);
		saveRoleOverride("explorer", { provider: "anthropic", id: "claude-haiku-4-5" }, path);
		assertEqual(loadRoleOverrides(path), {
			planner: { provider: "openai", id: "gpt-5" },
			explorer: { provider: "anthropic", id: "claude-haiku-4-5" },
		});
	});
});

test("resolveRoleModel prefers a saved override over the default", () => {
	const overrides = { builder: { provider: "openai", id: "gpt-5-mini" } };
	assertEqual(resolveRoleModel("builder", overrides), { provider: "openai", id: "gpt-5-mini" });
});

test("loadRoleOverrides ignores malformed JSON", () => {
	withTempDir((path) => {
		writeFileSync(path, "{ not valid json", "utf-8");
		assertEqual(loadRoleOverrides(path), {});
	});
});

test("loadRoleOverrides ignores unknown keys and malformed entries", () => {
	withTempDir((path) => {
		writeFileSync(
			path,
			JSON.stringify({
				planner: { provider: "openai", id: "gpt-5" },
				notARole: { provider: "x", id: "y" },
				builder: { provider: "missing-id-field" },
			}),
			"utf-8",
		);
		assertEqual(loadRoleOverrides(path), { planner: { provider: "openai", id: "gpt-5" } });
	});
});

console.log("\nAll role-store tests completed.");
