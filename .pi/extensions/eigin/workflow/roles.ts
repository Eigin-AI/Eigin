/**
 * Model roles: named purposes the workflow can reference (planner, builder,
 * explorer) instead of hardcoding a specific model per stage. Stages point at
 * a role; the actual model behind each role is configurable and persisted
 * separately (see role-store.ts), so "use the builder model" doesn't mean
 * "use Sonnet" forever — it means whatever you've currently assigned to
 * that role.
 */

export type RoleId = "planner" | "builder" | "explorer";

export interface RoleModel {
	provider: string;
	id: string;
}

export const ROLE_IDS: RoleId[] = ["planner", "builder", "explorer"];

export const ROLE_LABELS: Record<RoleId, string> = {
	planner: "Planner (big)",
	builder: "Builder (mid)",
	explorer: "Explorer (small)",
};

/** Built-in defaults, used until a role is overridden (see role-store.ts). */
export const ROLE_DEFAULTS: Record<RoleId, RoleModel> = {
	planner: { provider: "anthropic", id: "claude-opus-4-8" },
	builder: { provider: "anthropic", id: "claude-sonnet-5" },
	explorer: { provider: "anthropic", id: "claude-haiku-4-5" },
};

export function isRoleId(value: string): value is RoleId {
	return (ROLE_IDS as string[]).includes(value);
}
