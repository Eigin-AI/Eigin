/**
 * `/eigin:role` — show or set which model backs each workflow role
 * (planner/builder/explorer). Mirrors `/eigin:stage`: bare invocation opens an
 * interactive picker, arguments set directly.
 *
 * Named `/eigin:role`, not `/model`, because pi already has a built-in
 * `/model` command (session model selector) — this is a different,
 * higher-level concept: which model a *role* resolves to, not which model the
 * current session uses right now. Namespaced under `eigin:` (as are the other
 * commands this extension registers) to avoid colliding with other
 * extensions' commands.
 *
 * Usage:
 *   /eigin:role                          interactive: pick a role, then a model
 *   /eigin:role <role>                   interactive: pick a model for that role
 *   /eigin:role <role> <id>              set directly (searches all providers for id)
 *   /eigin:role <role> <provider>/<id>   set directly, unambiguous provider
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { ROLE_IDS, ROLE_LABELS, isRoleId, type RoleId, type RoleModel } from "../workflow/roles.ts";
import { loadRoleOverrides, resolveRoleModel, saveRoleOverride } from "../workflow/role-store.ts";

export interface RoleCommandDeps {
	/** The role backing the current stage, if any — used to decide whether
	 * "switch the live session now?" makes sense. Configuring a role that
	 * isn't the active stage's role (e.g. setting `planner` while you're in
	 * Iterate, whose role is `builder`) shouldn't prompt to switch models. */
	activeRole: () => RoleId | undefined;
}

/** Split "provider/id" into parts; bare "id" leaves provider undefined. */
export function parseModelSpec(spec: string): { provider?: string; id: string } {
	const slash = spec.indexOf("/");
	if (slash === -1) return { id: spec };
	return { provider: spec.slice(0, slash), id: spec.slice(slash + 1) };
}

/** Resolve a parsed spec against the model registry, searching all providers when unqualified. */
function findModel(
	ctx: ExtensionContext,
	spec: { provider?: string; id: string },
): { model: RoleModel } | { error: string } {
	if (spec.provider) {
		const found = ctx.modelRegistry.find(spec.provider, spec.id);
		if (!found) return { error: `No model "${spec.id}" for provider "${spec.provider}".` };
		return { model: { provider: found.provider, id: found.id } };
	}

	const matches = ctx.modelRegistry.getAll().filter((m) => m.id === spec.id);
	if (matches.length === 0) return { error: `No model matching "${spec.id}". Try "provider/${spec.id}".` };
	if (matches.length > 1) {
		const providers = matches.map((m) => m.provider).join(", ");
		return { error: `"${spec.id}" is ambiguous across providers (${providers}). Use "provider/${spec.id}".` };
	}
	return { model: { provider: matches[0].provider, id: matches[0].id } };
}

/**
 * Apply a role's model: persist the override, and — only when that role is
 * the one actually backing the current stage — offer to switch the live
 * session model now.
 */
async function applyRoleModel(
	ctx: ExtensionContext,
	pi: ExtensionAPI,
	role: RoleId,
	model: RoleModel,
	deps: RoleCommandDeps,
): Promise<void> {
	saveRoleOverride(role, model);
	ctx.ui.notify(`${ROLE_LABELS[role]} → ${model.id}`, "info");

	if (deps.activeRole() !== role) return;
	if (ctx.model?.provider === model.provider && ctx.model?.id === model.id) return;

	const ok = await ctx.ui.confirm(
		`Switch current model?`,
		`Also switch the live session to ${model.id} now? (current: ${ctx.model?.id ?? "none"})`,
	);
	if (!ok) return;

	const found = ctx.modelRegistry.find(model.provider, model.id);
	if (!found) return;
	const success = await pi.setModel(found);
	ctx.ui.notify(success ? `Model → ${model.id}` : `No API key for ${model.id}`, success ? "info" : "error");
}

async function pickModelForRole(ctx: ExtensionContext, pi: ExtensionAPI, role: RoleId, deps: RoleCommandDeps): Promise<void> {
	const available = ctx.modelRegistry.getAvailable();
	const list = available.length > 0 ? available : ctx.modelRegistry.getAll();
	if (list.length === 0) {
		ctx.ui.notify("No models available to pick from.", "error");
		return;
	}

	const current = resolveRoleModel(role, loadRoleOverrides());
	const labels = list.map((m) => `${m.provider}/${m.id}${m.provider === current.provider && m.id === current.id ? " (current)" : ""}`);
	const choice = await ctx.ui.select(`Model for ${ROLE_LABELS[role]}:`, labels);
	if (!choice) return;

	const model = list[labels.indexOf(choice)];
	await applyRoleModel(ctx, pi, role, { provider: model.provider, id: model.id }, deps);
}

async function pickRoleThenModel(ctx: ExtensionContext, pi: ExtensionAPI, deps: RoleCommandDeps): Promise<void> {
	const overrides = loadRoleOverrides();
	const labels = ROLE_IDS.map((r) => `${ROLE_LABELS[r]} — current: ${resolveRoleModel(r, overrides).id}`);
	const choice = await ctx.ui.select("Configure model for role:", labels);
	if (!choice) return;

	const role = ROLE_IDS[labels.indexOf(choice)];
	await pickModelForRole(ctx, pi, role, deps);
}

export function registerRoleCommand(pi: ExtensionAPI, deps: RoleCommandDeps): void {
	pi.registerCommand("eigin:role", {
		description: "Show or set the model for a role (planner|builder|explorer)",
		getArgumentCompletions: (prefix: string) => {
			const [first, ...rest] = prefix.split(/\s+/);
			if (rest.length > 0) return null;
			const matches = ROLE_IDS.filter((r) => r.startsWith(first));
			return matches.length > 0 ? matches.map((r) => ({ value: r, label: r })) : null;
		},
		handler: async (args, ctx) => {
			const parts = args.trim().split(/\s+/).filter(Boolean);

			if (parts.length === 0) {
				await pickRoleThenModel(ctx, pi, deps);
				return;
			}

			const [roleArg, ...modelParts] = parts;
			if (!isRoleId(roleArg)) {
				ctx.ui.notify(`Unknown role: "${roleArg}". Try: ${ROLE_IDS.join(", ")}`, "error");
				return;
			}

			if (modelParts.length === 0) {
				await pickModelForRole(ctx, pi, roleArg, deps);
				return;
			}

			const resolved = findModel(ctx, parseModelSpec(modelParts.join(" ")));
			if ("error" in resolved) {
				ctx.ui.notify(resolved.error, "error");
				return;
			}
			await applyRoleModel(ctx, pi, roleArg, resolved.model, deps);
		},
	});
}
