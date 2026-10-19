/**
 * Stretchtext controller: wires parsing/rendering/keyboard state into pi.
 *
 * - `message_end` records the latest assistant reply's text blocks and
 *   assigns digits 1-9 to its first openable stretches (pre-order).
 * - The markdown transformer renders every assistant text block with open
 *   state applied; footnote digits always show on the latest reply (the
 *   affordance marking a stretch as openable). Older replies keep whatever
 *   open state they had.
 * - ctrl+alt+e toggles number mode. While active, digits 1-9 toggle the
 *   matching stretch and are consumed; typing (or Enter) exits the mode and
 *   goes through as usual; key releases and modifier chords are ignored.
 * - The next fresh user turn after a reply carries a feedback note naming
 *   the stretches the reader opened (see feedback.ts).
 *
 * Re-render trick: pi exposes no invalidate for assistant messages, but
 * `ctx.ui.setHiddenThinkingLabel()` re-renders every AssistantMessageComponent
 * as a side effect, which re-runs the transformers. That's the refresh path
 * after every toggle.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { appendStageHintIfFreshTurn, type StageHintMessage } from "../workflow/stage-hint.ts";
import { buildFeedbackNote, type OpenedStretch } from "./feedback.ts";
import { collectOpenable, hasStretch, KEY_SEPARATOR, parse } from "./parse.ts";
import { defaultStyle, renderSegments, stretchtextStyle, type StretchStyle } from "./render.ts";

const MAX_DIGITS = 9;
const STATUS_KEY = "stretchtext";

interface AssistantTextMessage {
	role: string;
	content: Array<{ type: string; text?: string }>;
}

export function registerStretchtext(pi: ExtensionAPI): void {
	/** Latest assistant reply that contains openable stretches. */
	let latest: { message: unknown; blocks: string[] } | null = null;
	/** Per-block digit assignments (block text → stretch key → 1-9), latest reply only. */
	let digitsByBlock = new Map<string, Map<string, number>>();
	/** Open stretch keys per block text, for every reply (persists as replies age). */
	const openByBlock = new Map<string, Set<string>>();
	/** Stretch keys ever opened per block text, for the feedback note. */
	const openedByBlock = new Map<string, Set<string>>();
	/** The reply the feedback note was already sent for (object identity). */
	let reportedFor: unknown = null;
	let numbersActive = false;
	let uiCtx: ExtensionContext | null = null;
	let inputWired = false;
	/** Theme-less until the first event hands us a theme. */
	let style: StretchStyle = defaultStyle;

	/** Force every assistant message to re-render (see module comment). */
	const refresh = () => uiCtx?.ui.setHiddenThinkingLabel();

	const updateStatus = (ctx: ExtensionContext) =>
		ctx.ui.setStatus(STATUS_KEY, numbersActive ? "stretch: 1-9 toggle · any other key exits" : undefined);

	/**
	 * Record an assistant message as the latest stretchtext reply. Replies
	 * without openable stretches don't displace the current latest — numbers
	 * always target the most recent reply that actually has stretches.
	 */
	const adopt = (message: unknown, content: Array<{ type: string; text?: string }>) => {
		const blocks = content
			.filter((c) => c.type === "text" && typeof c.text === "string")
			.map((c) => c.text!.trim())
			.filter((t) => t.includes("{{"));
		const parsed = blocks.map((b) => parse(b));

		let n = 0;
		const digits = new Map<string, Map<string, number>>();
		let any = false;
		blocks.forEach((block, i) => {
			const forBlock = new Map<string, number>();
			for (const stretch of collectOpenable(parsed[i])) {
				any = true;
				if (n < MAX_DIGITS) forBlock.set(stretch.key, ++n);
			}
			digits.set(block, forBlock);
		});

		if (!any) return;
		digitsByBlock = digits;
		latest = { message, blocks };
	};

	pi.on("message_end", async (event) => {
		const message = event.message as AssistantTextMessage;
		if (message.role !== "assistant" || !Array.isArray(message.content)) return;
		adopt(event.message, message.content);
	});

	/**
	 * Register the digit interceptor and adopt the latest reply from history.
	 * Runs on the first event that carries a UI context, so a mid-session
	 * extension reload still ends up fully wired (session_start has already
	 * fired by then and won't fire again).
	 */
	const wireUi = (ctx: ExtensionContext) => {
		uiCtx = ctx;
		style = stretchtextStyle(ctx.ui.theme);
		if (inputWired || !ctx.hasUI) return;
		inputWired = true;

		ctx.ui.onTerminalInput((data) => {
			if (!numbersActive) return undefined;
			if (/^[1-9]$/.test(data)) {
				toggleDigit(Number(data));
				refresh();
				return { consume: true };
			}
			// Escape sequences (key releases, modifier chords, arrows) and control
			// bytes aren't typing — ignore them, stay in number mode. This is what
			// lets ctrl+alt+e's own key release pass without exiting the mode.
			if (data.includes("\x1b") || [...data].some((c) => c < " ")) {
				if (data === "\r" || data === "\n") {
					numbersActive = false;
					ctx.ui.setStatus(STATUS_KEY, undefined);
					refresh();
				}
				return undefined;
			}
			// Real typing (incl. backspace and paste): exit mode, input goes through.
			numbersActive = false;
			ctx.ui.setStatus(STATUS_KEY, undefined);
			refresh();
			return undefined;
		});

		// Catch up on the stretchtext reply that arrived before the extension
		// (re)loaded: scan back to the most recent reply with openable stretches.
		// It was already reported on when it was live, so mark it reported — a
		// resumed/reloaded session must not re-inject the feedback note for it.
		if (!latest) {
			const entries = ctx.sessionManager.getBranch();
			for (let i = entries.length - 1; i >= 0 && !latest; i--) {
				const entry = entries[i] as { type: string; message?: unknown };
				if (entry.type !== "message") continue;
				const message = entry.message as AssistantTextMessage;
				if (message?.role !== "assistant" || !Array.isArray(message.content)) continue;
				adopt(entry.message, message.content);
			}
			if (latest) reportedFor = latest.message;
		}
	};

	pi.registerMarkdownTransformer((markdown, context) => {
		if (context.messageType !== "assistant") return markdown;
		if (!markdown.includes("{{")) return markdown;
		const segments = parse(markdown);
		if (!hasStretch(segments)) return markdown;
		const open = openByBlock.get(markdown) ?? new Set<string>();
		// Footnote digits always show — the affordance marking a stretch as
		// openable. Number mode only arms the 1-9 toggling.
		const digits = digitsByBlock.get(markdown);
		return renderSegments(segments, { open, digits, style });
	});

	const toggleDigit = (digit: number) => {
		if (!latest) return;
		for (const block of latest.blocks) {
			const forBlock = digitsByBlock.get(block);
			if (!forBlock) continue;
			for (const [key, n] of forBlock) {
				if (n !== digit) continue;
				const open = openByBlock.get(block) ?? new Set<string>();
				if (open.has(key)) {
					// Close the stretch and everything nested inside it.
					for (const k of [...open]) {
						if (k === key || k.startsWith(key + KEY_SEPARATOR)) open.delete(k);
					}
				} else {
					open.add(key);
					const opened = openedByBlock.get(block) ?? new Set<string>();
					opened.add(key);
					openedByBlock.set(block, opened);
				}
				openByBlock.set(block, open);
				return;
			}
		}
	};

	const toggleNumberMode = (ctx: ExtensionContext) => {
		wireUi(ctx);
		if (!latest) {
			ctx.ui.notify("No stretchtext reply yet.", "info");
			return;
		}
		numbersActive = !numbersActive;
		updateStatus(ctx);
		if (numbersActive) {
			const count = Math.max(0, ...[...digitsByBlock.values()].flatMap((m) => [...m.values()]));
			ctx.ui.notify(`Stretch numbers on: 1-${Math.max(count, 1)} toggle stretches on the latest reply.`, "info");
		}
		refresh();
	};

	pi.registerShortcut("ctrl+alt+e", {
		description: "Stretchtext: show 1-9 numbers on the latest reply's stretches",
		handler: async (ctx) => toggleNumberMode(ctx),
	});

	// Command fallback for terminals where ctrl+alt+e doesn't reach pi.
	pi.registerCommand("eigin:stretch", {
		description: "Stretchtext: toggle 1-9 numbers on the latest reply's stretches",
		handler: async (_args, ctx) => toggleNumberMode(ctx),
	});

	pi.on("session_start", async (_event, ctx) => wireUi(ctx));

	// Mid-session reloads miss session_start; every turn carries a UI context.
	pi.on("before_agent_start", async (_event, ctx) => {
		wireUi(ctx);
	});

	pi.on("context", async (event) => {
		if (!latest || reportedFor === latest.message) return;
		const msgs = event.messages as StageHintMessage[];
		if (msgs[msgs.length - 1]?.role !== "user") return;
		reportedFor = latest.message;

		const stretches: OpenedStretch[] = [];
		for (const block of latest.blocks) {
			const opened = openedByBlock.get(block) ?? new Set<string>();
			for (const stretch of collectOpenable(parse(block))) {
				stretches.push({ short: stretch.short, opened: opened.has(stretch.key) });
			}
		}
		const note = buildFeedbackNote(stretches);
		if (!note) return;
		const messages = appendStageHintIfFreshTurn(msgs, note);
		return { messages: messages as unknown as typeof event.messages };
	});
}
