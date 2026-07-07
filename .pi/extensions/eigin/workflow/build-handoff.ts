/**
 * Plan→Build handoff: composes the compaction instructions and the kickoff
 * message used when transitioning from the Plan stage into the Build stage.
 *
 * Pure/IO-free by design (file reads and stage/model wiring live in
 * index.ts) so the composition logic is plain-node-testable.
 */

/**
 * Custom instructions passed to `ctx.compact()` on the Plan→Build transition.
 * Steers the summary toward *why* the plan looks the way it does (decisions,
 * constraints, rejected alternatives, discoveries) rather than a generic
 * blow-by-blow — the plan file itself already has the "what".
 */
export function buildCompactionInstructions(planPath: string | null): string {
	const base =
		"We're transitioning from planning to implementation. Summarize the " +
		"decisions made, constraints and discoveries surfaced, and any " +
		"alternatives considered and rejected during the Context and Plan " +
		"stages. Focus on *why* the plan looks the way it does, not a " +
		"blow-by-blow of the conversation.";
	if (!planPath) return base;
	return `${base} The approved plan is saved at ${planPath} — no need to reproduce its contents in the summary.`;
}

/**
 * The message auto-sent to kick off the Build stage once compaction and the
 * model switch have completed. Inlines the plan so Build has the full spec
 * even though the surrounding discussion was just compacted away.
 */
export function buildKickoff(planPath: string | null, planContent: string | null): string {
	if (planPath && planContent) {
		return [
			`We've approved the plan at \`${planPath}\`. Implement it.`,
			"",
			"---",
			planContent.trim(),
			"---",
			"",
			"Proceed.",
		].join("\n");
	}
	return "Implement what we agreed above. Proceed.";
}
