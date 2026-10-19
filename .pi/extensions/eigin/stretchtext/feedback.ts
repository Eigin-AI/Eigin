/**
 * The per-turn note telling the model which stretches the reader opened
 * since its last reply — the feedback half of the stretchtext loop. Reported
 * once per reply, on the next fresh user turn.
 */

export interface OpenedStretch {
	short: string;
	opened: boolean;
}

export function buildFeedbackNote(stretches: OpenedStretch[]): string | null {
	if (stretches.length === 0) return null;
	const quote = (list: string[]) => list.map((s) => `"${s}"`).join(", ");
	const opened = stretches.filter((s) => s.opened).map((s) => s.short.trim());
	const unopened = stretches.filter((s) => !s.opened).map((s) => s.short.trim());

	const body =
		opened.length > 0
			? `Stretchtext: since your last reply the reader opened ${quote(opened)}.` +
				(unopened.length > 0 ? ` They did not open ${quote(unopened)}.` : "")
			: "Stretchtext: the reader opened none of the stretches in your last reply — they may have read only the short forms.";

	// Same ride-on-user-message guards as buildStageHint, so the two sibling
	// injections look alike.
	return `\n\n---\n[Automatically injected — not part of the user's message]\n${body}\n---`;
}
