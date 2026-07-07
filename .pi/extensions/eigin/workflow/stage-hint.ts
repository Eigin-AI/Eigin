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

/** Build the stage hint block appended to the user's message. */
export function buildStageHint(stageLabel: string, guidance: string): string {
	return (
		`\n\n---\n[Automatically injected — not part of the user's message]\n` +
		`Current workflow stage: ${stageLabel}\n${guidance}\n---`
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
