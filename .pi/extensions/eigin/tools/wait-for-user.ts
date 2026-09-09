/**
 * wait_for_user — hand control back to the user and block until they signal.
 *
 * The anti-prose mechanism of the collaborative flow: instead of ending a turn
 * with a wall of text explaining what to do, the agent opens a small confirm
 * ("edit the plan / comment on the MR — confirm when you're ready") and waits.
 * When the user confirms, the tool returns and the agent continues in the same
 * turn — re-reading the plan file (Plan stage) or pulling MR comments (Merge).
 *
 * Reuses the shared confirm-with-note dialog so the user can attach a quick
 * note ("also look at X") along with the ready signal.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { confirmWithNote } from "./confirm-dialog.ts";
import { withHerdrBlocked } from "../observability/herdr.ts";

export const WAIT_FOR_USER_TOOL = "wait_for_user";

/**
 * Lets the tool deliver the right payload on confirm without knowing the
 * extension's internals: the current stage id, and (Plan stage) the live plan
 * file + a diff of the user's edits. This is what makes pressing "ready"
 * surface the diff directly — the per-turn context injection only fires on
 * fresh user-typed turns, not on a tool continuation like this one.
 */
export interface WaitForUserController {
	stage(): string;
	planInjection(): Promise<string | null>;
	/** AFK mode signals "ready" immediately without blocking on the user. */
	isAfk(): boolean;
}

export function registerWaitForUserTool(pi: ExtensionAPI, controller: WaitForUserController): void {
	pi.registerTool({
		name: WAIT_FOR_USER_TOOL,
		label: "Wait for User",
		description:
			"Hand control back to the user and block until they signal they're ready for you to continue. " +
			"Use instead of ending your turn with a long explanation: while co-editing the plan, or while the " +
			"user reviews the MR. Pass a short `prompt` telling them what to do, and a `confirmLabel` naming the " +
			"exact action the confirm button performs (e.g. 'Review my plan edits', 'Pull my comments') — not a " +
			"vague 'ready', which reads as ambiguous. This is NOT the approve gate: never mention advancing or moving " +
			"stages in the prompt or confirmLabel — use propose_stage for that, as its own separate step. On confirm " +
			"the result hands back the plan + a diff of the user's edits (Plan stage), or tells you to pull the MR " +
			"comments (Merge stage) — act on it in the same turn.",
		promptSnippet: "Hand control to the user and block until they confirm they're ready",
		promptGuidelines: [
			"Prefer wait_for_user over walls of prose: after doing your part, call it with a short prompt and a confirmLabel naming the confirm action (e.g. 'Review my plan edits', 'Pull my comments'), instead of explaining at length. It is not the approve gate — use propose_stage for that.",
		],
		parameters: Type.Object({
			prompt: Type.Optional(
				Type.String({
					description:
						"Short line telling the user what to do (e.g. 'Edit the plan directly, then continue when you're done').",
				}),
			),
			confirmLabel: Type.Optional(
				Type.String({
					description:
						"Label for the confirm button, naming what it does for the user — e.g. 'Review my plan edits' or 'Pull my comments'. Defaults to 'Continue — take a look'.",
				}),
			),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx) {
			const detail = params.prompt?.trim() || "Make your edits, then continue when you'd like me to take a look.";
			const confirmLabel = params.confirmLabel?.trim() || "Continue — take a look";

			if (ctx.mode !== "tui" || !ctx.hasUI) {
				return {
					content: [
						{ type: "text", text: "No interactive UI to wait on — continuing without a pause." },
					],
					details: { waited: false },
				};
			}

			// AFK: don't wait — proceed as if the user signalled ready, so the agent
			// re-reads the plan (Plan) or pulls MR comments (Merge) and moves on.
			const result = controller.isAfk()
				? { confirmed: true }
				: await withHerdrBlocked(pi, "Over to you", () =>
					confirmWithNote(ctx.ui, "Over to you", detail, [confirmLabel, "Stop — I'll type instead"]),
				);

			// Esc or "Stop" — the user doesn't want to signal now. End the turn
			// quietly; they'll send a normal message when they're ready.
			if (!result || !result.confirmed) {
				return {
					content: [
						{
							type: "text",
							text: "The user hasn't signalled yet. Ending the turn — they'll message when ready.",
						},
					],
					details: { waited: true, ready: false },
					terminate: true,
				};
			}

			const noteLine = result.note ? ` The user added: "${result.note}".` : "";
			const stage = controller.stage();
			let followup: string;
			if (stage === "plan") {
				const injection = await controller.planInjection();
				followup = injection
					? `${injection}\n\nAddress the user's edits above, then APPEND a Decision log entry and hand back.`
					: "Re-read the plan file and address the user's edits, then append a Decision log entry.";
			} else if (stage === "merge") {
				followup =
					"Pull the MR's unresolved comments (paginate), turn actionable ones into tasks, address them, and reply per-thread prefixed \"**Agent**:\".";
			} else {
				followup = "Continue with what the user asked.";
			}
			return {
				content: [{ type: "text", text: `The user is done.${noteLine}\n\n${followup}` }],
				details: { waited: true, ready: true, stage, note: result.note },
			};
		},
	});
}
