/**
 * Composes the kickoff message that hands a branch to the reviewer sub-agent.
 *
 * Two triggers, one message: the Merge handoff (index.ts), where the review
 * runs before the MR is opened, and `/eigin:review` (tools/review-command.ts),
 * where it's an on-demand check.
 *
 * Pure/IO-free by design (the git diff, file writes and stage wiring live in
 * their callers) so the composition logic is plain-node-testable.
 */

/** The guide the reviewer judges the diff against. */
export const REVIEW_GUIDE = ".pi/guidance/review-guide.md";

export interface ReviewHandoff {
	/** Where the branch diff was written. */
	diffPath: string;
	/** The approved plan, when the workflow produced one. */
	planPath: string | null;
	/** The review guide the reviewer judges against. */
	guidePath: string;
	/** True at the Merge handoff, where the MR follows the review. */
	atMerge: boolean;
}

/**
 * The message auto-sent once the diff has been written. At the Merge handoff
 * this runs first so the MR opens on already-addressed feedback rather than
 * carrying it into the user's own review.
 */
export function reviewKickoff({ diffPath, planPath, guidePath, atMerge }: ReviewHandoff): string {
	const planLine = planPath ? `\n- The plan: \`${planPath}\`` : "";
	const opening = atMerge
		? "Before opening the MR, get a fresh-eyes review of this branch."
		: "Get a fresh-eyes review of this branch.";
	const closing = atMerge
		? "Then continue with the Merge stage and open the MR."
		: "Then stop and hand back to the user — this is a check-in, not the merge handoff.";
	return [
		opening,
		"",
		`Call the \`subagent\` tool with agent \`reviewer\`. Give it these paths:`,
		`- The diff: \`${diffPath}\``,
		`- The review guide: \`${guidePath}\`${planLine}`,
		"",
		"When it reports back:",
		"- Add its findings as tasks, must-fix first.",
		"- Fix what it found, then clear those tasks. Push back in chat on anything you disagree with rather than fixing it quietly.",
		"- Summarize for the user what was flagged and what you changed.",
		"",
		closing,
	].join("\n");
}
