/**
 * Resolves a `role:<name>` sentinel in an agent's `model` frontmatter field
 * against our workflow/roles.ts role store — the seam that couples the
 * vendored subagent tool to our own role system.
 *
 * Kept in its own file (rather than inline in agents.ts) so it has no
 * dependency on `@earendil-works/pi-coding-agent`, which only resolves under
 * pi's own module loader — this way the pure logic stays plain-`node`-testable.
 */

import { loadRoleOverrides, resolveRoleModel, type RoleOverrides } from "../../workflow/role-store.ts";
import { isRoleId, type RoleModel } from "../../workflow/roles.ts";

const ROLE_PREFIX = "role:";

/** Format a RoleModel as the "provider/id" string pi's --model flag expects. */
function formatModelFlag(model: RoleModel): string {
	return `${model.provider}/${model.id}`;
}

/**
 * Resolve an agent's `model` frontmatter value. A `role:<name>` sentinel
 * (e.g. `role:explorer`) resolves against the role store; anything else
 * (a literal model id, or undefined) passes through unchanged. An unknown
 * role name degrades gracefully to undefined rather than crashing discovery
 * (pi falls back to the default model for that case).
 */
export function resolveAgentModel(model: string | undefined, overrides: RoleOverrides = loadRoleOverrides()): string | undefined {
	if (!model || !model.startsWith(ROLE_PREFIX)) return model;

	const role = model.slice(ROLE_PREFIX.length);
	if (!isRoleId(role)) return undefined;

	return formatModelFlag(resolveRoleModel(role, overrides));
}
