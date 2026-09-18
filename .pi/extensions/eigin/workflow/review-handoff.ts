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
 * The message auto-sent once the diff has been written: a two-round protocol
 * — an initial review, then exactly one verification round on the builder's
 * response. The message is the spec.
 */
export function reviewKickoff({ diffPath, planPath, guidePath, atMerge }: ReviewHandoff): string {
	const planLine = planPath ? `\n- The plan: \`${planPath}\`` : "";
	const paths = [`- The diff: \`${diffPath}\``, `- The review guide: \`${guidePath}\`${planLine}`].join("\n");
	const opening = atMerge
		? "Before opening the MR, get a fresh-eyes review of this branch."
		: "Get a fresh-eyes review of this branch.";
	const closing = atMerge
		? "Then continue with the Merge stage and open the MR."
		: "Then stop and hand back to the user — this is a check-in, not the merge handoff.";
	return [
		opening,
		"Run it in two rounds: an initial review, then one verification round on your response.",
		"",
		"## Round 1 — review",
		"",
		"Call the `subagent` tool with agent `reviewer`. Give it these paths:",
		paths,
		"",
		"When it reports back:",
		"- Add its findings as tasks, must-fix first.",
		"- Fix what it found, then clear those tasks.",
		"- Anything you disagree with, don't fix — hold it as pushback, with your reason.",
		"",
		"## Round 2 — verification (exactly once)",
		"",
		"Call `reviewer` again. Give it:",
		"- The round-1 report, verbatim.",
		"- Your response: what you fixed (file:line) and each pushback, with reasons.",
		"- The paths from round 1.",
		"The diff on disk predates the fixes — tell the reviewer to run `git diff main` (read-only) for the current state.",
		"",
		"Ask it to apply the same review guide a second time: did the fixes land, did anything slip through, and is each pushback justified? Anything unjustified it re-raises as must-fix.",
		"Fix whatever it re-raised. There is no third round.",
		"",
		"Then summarize for the user: what was flagged, what you changed, what you pushed back on and why, and what round 2 re-raised.",
		"",
		closing,
	].join("\n");
}
