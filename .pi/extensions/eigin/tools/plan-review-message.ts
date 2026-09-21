/**
 * plan_review's decision rendering — the guidance contract between the
 * Plannotator review decision and what the agent does next. Pure, so it's
 * testable without pi's tool runtime (see plan-review.ts for the tool itself).
 */

/** What the agent needs to react to the human's decision. */
export interface PlanReviewDecision {
	approved: boolean;
	feedback?: string;
}

export interface PlanReviewResult {
	kind: "decision" | "closed-without-decision";
	decision?: PlanReviewDecision;
	message: string;
}

/** The agent-facing text for a decision. */
export function formatDecision(decision: PlanReviewDecision): string {
	if (decision.approved && decision.feedback?.trim()) {
		return (
			"The plan was APPROVED with notes in the review UI. The notes are guidance for Build, not a rework " +
			`list:\n\n${decision.feedback.trim()}\n\nAPPEND a Decision log entry, then call propose_stage(build) ` +
			"if the plan is otherwise fully formed."
		);
	}
	if (decision.approved) {
		return (
			"The plan was APPROVED in the review UI. APPEND a Decision log entry, then call propose_stage(build) " +
			"if the plan is fully formed."
		);
	}
	return (
		"The reviewer requested changes in the review UI. Address the feedback, update the plan file, and APPEND " +
		"a Decision log entry — then call plan_review again to resubmit (Plannotator will diff it against this " +
		`version).\n\nFeedback:\n${decision.feedback?.trim() ?? "(none)"}`
	);
}

/** Pure bridge between a raw Plannotator review result and what the tool reports. */
export function toPlanReviewResult(event: PlanReviewDecision): PlanReviewResult {
	if (!event.approved && !event.feedback?.trim()) {
		return {
			kind: "closed-without-decision",
			message:
				"The reviewer closed the review without a decision. Fall back to the collaborative co-editing loop " +
				"(wait_for_user) or ask directly what they'd like changed.",
		};
	}
	const decision = { approved: event.approved, feedback: event.feedback };
	return { kind: "decision", decision, message: formatDecision(decision) };
}
