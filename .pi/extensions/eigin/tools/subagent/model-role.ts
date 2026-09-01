/**
 * Resolves which model a sub-agent runs on: a `role:<name>` sentinel in its
 * `model` frontmatter against our workflow/roles.ts role store, and the
 * session's own model for an agent that pins nothing. The seam that couples
 * the vendored subagent tool to our own role system.
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

/**
 * Fill in the session's current model for agents that don't pin one. Without
 * this an unpinned agent falls back to pi's configured default, which is
 * rarely the model you're working with once a stage has switched it.
 */
export function applySessionModel<T extends { model?: string }>(
	agents: T[],
	sessionModel: RoleModel | undefined,
): T[] {
	if (!sessionModel) return agents;
	const flag = formatModelFlag(sessionModel);
	return agents.map((agent) => (agent.model ? agent : { ...agent, model: flag }));
}
