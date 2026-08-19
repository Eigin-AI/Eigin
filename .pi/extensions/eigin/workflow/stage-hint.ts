/**
 * Per-turn stage hint, appended to the latest user message instead of the
 * system prompt.
 *
 * Why not the system prompt: Anthropic-style prompt caching (see
 * `cacheControlFormat` in pi's models.md) places cache breakpoints on the
 * system prompt, the last tool definition, and the last user/assistant text
 * content. The system prompt + tool defs form one large, stable, cached
 * prefix. Stage guidance changes every time the stage changes, so putting it
 * in the system prompt invalidates that entire cached prefix on every
 * transition. The last message, by contrast, is never reused from a previous
 * call — it's always new content — so appending the same information there
 * costs nothing extra relative to not having it at all.
 */

export interface StageHintMessage {
	role: string;
	content: string | Array<{ type: string; text?: string; [key: string]: unknown }>;
}

/** A stage as it appears in the active workflow's ordered sequence. */
export interface StageHintStage {
	id: string;
	label: string;
}

/**
 * The active workflow's stage sequence, for rendering into the hint. This is
 * what makes `propose_stage` targets discoverable: the agent sees exactly
 * which stages this workflow has (and which one it's on) instead of guessing
 * from the tool's full 7-stage vocabulary, some of which a given workflow
 * may not include (e.g. Bug has no Review; Prototype has no Build).
 */
export interface WorkflowStageView {
	workflowLabel: string;
	workflowIcon: string;
	stages: StageHintStage[];
	currentId: string;
}

/** Build the stage hint block appended to the user's message. */
export function buildStageHint(view: WorkflowStageView, guidance: string): string {
	const sequence = view.stages
		.map((s) => (s.id === view.currentId ? `[${s.label}]` : s.label))
		.join(" → ");
	const idx = view.stages.findIndex((s) => s.id === view.currentId);
	const next = idx >= 0 && idx < view.stages.length - 1 ? view.stages[idx + 1] : undefined;
	const others = view.stages.filter((s) => s.id !== view.currentId).map((s) => s.id);
	const current = view.stages.find((s) => s.id === view.currentId);
	const currentLabel = current ? current.label : view.currentId;
	const targetsLine = next
		? `To advance, call propose_stage with NO stage — it goes to the next stage (${next.id}). Only pass a named stage to skip ahead or step back, which should be rare. Valid stages: ${others.join(", ")}.`
		: others.length > 0
			? `You're at the last stage. To step back, call propose_stage with one of: ${others.join(", ")}.`
			: "This workflow has no other stages to move to.";
	const proposeDirectly = next
		? `\nWhen this stage's work is done, call propose_stage directly — that dialog IS the ask. Don't ask in prose ("should we go to ${next.id}?") and then also propose; just propose, and the user can decline.`
		: "";
	return (
		`\n\n---\n[Automatically injected — not part of the user's message]\n` +
		`Workflow: ${view.workflowIcon} ${view.workflowLabel} — ${sequence}\n` +
		`Current workflow stage: ${currentLabel}\n${targetsLine}${proposeDirectly}\n${guidance}\n---`
	);
}

/**
 * Append the stage hint to the last message in `messages`, but only when
 * that message is a fresh user turn (not a tool-result/assistant message from
 * mid-turn continuation). This mirrors the old before_agent_start behavior of
 * injecting once per user prompt, rather than on every provider call within a
 * multi-tool-call turn — earlier turns already carry the hint they had when
 * they were sent, preserved in the cached conversation prefix.
 *
 * Returns a new array; never mutates the input.
 */
export function appendStageHintIfFreshTurn<T extends StageHintMessage>(messages: T[], hint: string): T[] {
	if (messages.length === 0) return messages;

	const last = messages[messages.length - 1];
	if (last.role !== "user") return messages;

	const content =
		typeof last.content === "string"
			? [{ type: "text", text: last.content }, { type: "text", text: hint }]
			: [...last.content, { type: "text", text: hint }];

	const patched = { ...last, content };
	return [...messages.slice(0, -1), patched];
}
