/**
 * Persists per-developer overrides for role→model assignments.
 *
 * Stored at `.pi/model-roles.json`, gitignored — this is a personal
 * preference (which model you want behind "the builder model"), not a shared
 * team default. The shared fallback lives in code (ROLE_DEFAULTS in
 * roles.ts) and is what a fresh checkout gets with no override file.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { ROLE_DEFAULTS, ROLE_IDS, type RoleId, type RoleModel } from "./roles.ts";

// This file lives at .pi/extensions/eigin/workflow/role-store.ts; the
// overrides file lives alongside .pi/settings.json.
const PI_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
export const DEFAULT_OVERRIDES_PATH = join(PI_DIR, "model-roles.json");

export type RoleOverrides = Partial<Record<RoleId, RoleModel>>;

function isRoleModel(value: unknown): value is RoleModel {
	if (typeof value !== "object" || value === null) return false;
	const candidate = value as Record<string, unknown>;
	return typeof candidate.provider === "string" && typeof candidate.id === "string";
}

/** Load saved overrides, ignoring anything malformed. Missing file → no overrides. */
export function loadRoleOverrides(path: string = DEFAULT_OVERRIDES_PATH): RoleOverrides {
	if (!existsSync(path)) return {};

	let parsed: unknown;
	try {
		parsed = JSON.parse(readFileSync(path, "utf-8"));
	} catch {
		return {};
	}
	if (typeof parsed !== "object" || parsed === null) return {};

	const overrides: RoleOverrides = {};
	for (const role of ROLE_IDS) {
		const value = (parsed as Record<string, unknown>)[role];
		if (isRoleModel(value)) overrides[role] = value;
	}
	return overrides;
}

/** Save a single role's override, preserving any other roles already saved. */
export function saveRoleOverride(role: RoleId, model: RoleModel, path: string = DEFAULT_OVERRIDES_PATH): void {
	const current = loadRoleOverrides(path);
	current[role] = model;
	mkdirSync(dirname(path), { recursive: true });
	writeFileSync(path, `${JSON.stringify(current, null, 2)}\n`, "utf-8");
}

/** The effective model for a role: saved override, or the built-in default. */
export function resolveRoleModel(role: RoleId, overrides: RoleOverrides): RoleModel {
	return overrides[role] ?? ROLE_DEFAULTS[role];
}
