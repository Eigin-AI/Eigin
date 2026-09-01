/**
 * `/eigin:review` — run the reviewer over the current branch on demand.
 *
 * The same review the Merge handoff offers (see workflow/review-handoff.ts),
 * available at any point: mid-build to check direction, or again after
 * addressing findings. Typing the command is the confirmation, so unlike the
 * handoff it doesn't ask first.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { writeBranchDiff } from "../workflow/branch-diff.ts";
import { REVIEW_GUIDE, reviewKickoff } from "../workflow/review-handoff.ts";

export interface ReviewCommandDeps {
	/** Path of the active plan file, if any — the reviewer judges against it. */
	activePlanPath: () => string | undefined;
	/** The session's working directory. */
	sessionCwd: () => string;
}

export function registerReviewCommand(pi: ExtensionAPI, deps: ReviewCommandDeps): void {
	pi.registerCommand("eigin:review", {
		description: "Review this branch's changes against the review guide",
		handler: async (_args: string, ctx: ExtensionContext) => {
			const cwd = deps.sessionCwd();

			let diffPath: string | null;
			try {
				diffPath = await writeBranchDiff(cwd);
			} catch (err) {
				ctx.ui.notify(`Couldn't build the diff: ${err instanceof Error ? err.message : String(err)}`, "error");
				return;
			}

			if (!diffPath) {
				ctx.ui.notify("Nothing to review — no changes against main.", "warning");
				return;
			}

			const relative = diffPath.replace(`${cwd}/`, "");
			ctx.ui.notify(`Reviewing ${relative}…`, "info");
			pi.sendUserMessage(
				reviewKickoff({
					diffPath: relative,
					planPath: deps.activePlanPath() ?? null,
					guidePath: REVIEW_GUIDE,
				}),
			);
		},
	});
}
