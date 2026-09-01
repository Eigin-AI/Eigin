/**
 * `/eigin:plan` — work with the active collaborative plan file.
 *
 * The Plan stage co-edits a markdown file under `.pi/plans/` (tracked as the
 * active plan; see workflow/active-plan.ts). This command opens that file in
 * the user's own editor so they can edit it wherever they like — on demand,
 * never automatically, and never coupled to a specific tool.
 *
 * Editor choice follows the usual convention: $VISUAL, then $EDITOR, then the
 * platform's default opener (`open`/`xdg-open`/`start`) so a GUI markdown app
 * handles it when no editor var is set.
 *
 * Usage:
 *   /eigin:plan        show the active plan file's path
 *   /eigin:plan open   open the active plan file in your editor
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";
import { resolve } from "node:path";

export interface PlanCommandDeps {
	/** Absolute-or-repo-relative path of the active plan file, if any. */
	activePlanPath: () => string | undefined;
	/** The session's working directory, for resolving a relative plan path. */
	sessionCwd: () => string;
}

/** The editor command to open a file with, following $VISUAL/$EDITOR then the OS opener. */
function resolveOpener(): { command: string; args: string[] } {
	const editor = process.env.VISUAL?.trim() || process.env.EDITOR?.trim();
	if (editor) {
		// $VISUAL/$EDITOR may include flags (e.g. "code -w"); split on spaces.
		const [command, ...flags] = editor.split(/\s+/);
		return { command, args: flags };
	}
	if (process.platform === "darwin") return { command: "open", args: [] };
	if (process.platform === "win32") return { command: "cmd", args: ["/c", "start", ""] };
	return { command: "xdg-open", args: [] };
}

/** Launch the editor detached so it never blocks or ties to the TUI's lifetime. */
function openInEditor(absPath: string): void {
	const { command, args } = resolveOpener();
	const child = spawn(command, [...args, absPath], { detached: true, stdio: "ignore" });
	child.unref();
}

export function registerPlanCommand(pi: ExtensionAPI, deps: PlanCommandDeps): void {
	pi.registerCommand("eigin:plan", {
		description: "Show or open the active plan file (open it in your editor)",
		getArgumentCompletions: (prefix: string) => {
			const items = ["open"].filter((o) => o.startsWith(prefix));
			return items.length > 0 ? items.map((o) => ({ value: o, label: o })) : null;
		},
		handler: async (args: string, ctx: ExtensionContext) => {
			const arg = args.trim().toLowerCase();
			const path = deps.activePlanPath();

			if (!path) {
				ctx.ui.notify("No active plan file yet — one is tracked once written in the Plan stage.", "warning");
				return;
			}

			if (arg === "") {
				ctx.ui.notify(`Active plan: ${path}\nRun /eigin:plan open to edit it in your editor.`, "info");
				return;
			}

			if (arg === "open") {
				const abs = resolve(deps.sessionCwd(), path);
				try {
					openInEditor(abs);
					ctx.ui.notify(`Opening ${path}…`, "info");
				} catch (err) {
					ctx.ui.notify(
						`Couldn't open the plan: ${err instanceof Error ? err.message : String(err)}. Set $VISUAL or $EDITOR.`,
						"error",
					);
				}
				return;
			}

			ctx.ui.notify(`Unknown argument: "${arg}". Try: /eigin:plan open`, "error");
		},
	});
}
