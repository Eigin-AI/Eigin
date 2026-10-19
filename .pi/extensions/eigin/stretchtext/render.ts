/**
 * Render parsed stretchtext segments back to markdown for pi's Markdown
 * component, applying the reader's open/closed state.
 *
 * - Closed stretch: short form styled with `style.closed` (default ANSI bold,
 *   themed accent+underline once a theme is captured), digit superscript
 *   appended — the footnote always shows, marking the stretch as openable.
 * - Open stretch: long form rendered in place. The short form's words keep
 *   the closed style in place (nothing moves in front); newly revealed
 *   words take `style.added`; « collapse marker + digit superscript at the end.
 * - Unterminated (streaming) or pipe-less stretches: short form as plain text.
 * - Multi-line short forms: drawn fully open, no collapse marker.
 *
 * Styles are raw-ANSI producers: pi's Markdown component passes ANSI through
 * and re-applies open styles across wrapped lines, so colored spans are safe.
 */

import { isCode, isOpenable, isStretch, type Segment, type Stretch } from "./parse.ts";

const SUPERSCRIPTS = ["", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"];

export function superscript(n: number): string {
	return SUPERSCRIPTS[n] ?? String(n);
}

/** How each stretchtext element is drawn. Functions produce raw ANSI. */
export interface StretchStyle {
	/** Short form of a closed stretch. */
	closed: (text: string) => string;
	/** Newly revealed words of an open stretch. */
	added: (text: string) => string;
	/** Digit labels. */
	marker: (text: string) => string;
	/** The « collapse marker on an open stretch. */
	collapse: (text: string) => string;
}

/** Theme-less fallback: bold (the only emphasis markdown gives us). */
export const defaultStyle: StretchStyle = {
	closed: (text) => `\x1b[1m${text}\x1b[22m`,
	added: (text) => text,
	marker: (text) => text,
	collapse: (text) => `\x1b[1m${text}\x1b[22m`,
};

/**
 * Themed style: closed stretches underlined in accent color (distinct from
 * ordinary bold); when open, the already-read words keep that style and the
 * newly revealed words are underlined in muted — a soft shade, not a reset.
 */
export function stretchtextStyle(theme: { fg: (color: string, text: string) => string }): StretchStyle {
	return {
		closed: (text) => `\x1b[4m${theme.fg("accent", text)}\x1b[24m`,
		added: (text) => `\x1b[4m${theme.fg("muted", text)}\x1b[24m`,
		marker: (text) => theme.fg("accent", text),
		collapse: (text) => theme.fg("accent", text),
	};
}

export interface RenderState {
	/** Keys of stretches the reader has open. */
	open: ReadonlySet<string>;
	/** Stretch key → 1-9 label (always rendered — the openable affordance). */
	digits?: ReadonlyMap<string, number>;
	style: StretchStyle;
}

export function renderSegments(segments: Segment[], state: RenderState): string {
	return segments.map((seg) => renderSegment(seg, state)).join("");
}

function renderSegment(seg: Segment, state: RenderState): string {
	if (typeof seg === "string" || isCode(seg)) return isCode(seg) ? seg.text : seg;

	if (!isOpenable(seg)) {
		// No `|` yet (or ever), or the closing `}}` hasn't streamed in: show the
		// short form as plain text. A multi-line short renders fully open.
		if (seg.long === undefined || !seg.terminated) return seg.short;
		return renderSegments(seg.long, state);
	}

	const digit = state.digits?.get(seg.key);
	const mark = digit === undefined ? "" : state.style.marker(superscript(digit));

	if (state.open.has(seg.key)) {
		// Digit rides at the end, next to « — opening adds nothing in front of
		// words the reader has already seen.
		return renderOpen(seg, state) + " " + state.style.collapse("«") + mark;
	}
	return wrapPreservingSpaces(seg.short, state.style.closed) + mark;
}

/** A long form flattened to display items: words, separators, nested stretches, code spans. */
type Item =
	| { type: "word" | "sep"; text: string }
	| { type: "stretch"; stretch: Stretch }
	| { type: "code"; text: string };

function flattenItems(segments: Segment[]): Item[] {
	const items: Item[] = [];
	for (const seg of segments) {
		if (isStretch(seg)) {
			items.push({ type: "stretch", stretch: seg });
			continue;
		}
		if (isCode(seg)) {
			items.push({ type: "code", text: seg.text });
			continue;
		}
		for (const part of seg.split(/(\s+)/)) {
			if (!part) continue;
			items.push(/^\s+$/.test(part) ? { type: "sep", text: part } : { type: "word", text: part });
		}
	}
	return items;
}

/**
 * Indices of word items that are the short form's words, matched in order
 * (cc-stretch's anchors). Words compare punctuation-stripped, so a short
 * form ending "…color" matches a long form's "color,". If any short word is
 * missing — the model broke the "keep every word" promise — return null:
 * render everything plain.
 */
function anchorIndices(short: string, items: Item[]): Set<number> | null {
	const strip = (w: string) => w.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, "");
	const shortWords = short.trim().split(/\s+/).map(strip).filter(Boolean);
	const anchors = new Set<number>();
	let from = 0;
	for (const word of shortWords) {
		let found = -1;
		for (let i = from; i < items.length; i++) {
			const item = items[i];
			if (item.type === "word" && strip(item.text) === word) {
				found = i;
				break;
			}
		}
		if (found === -1) return null;
		anchors.add(found);
		from = found + 1;
	}
	return anchors;
}

/**
 * Open stretch: consecutive short-form words (with the whitespace between
 * them) form one styled run, so underlines persist through spaces; same for
 * the newly revealed words. Nested stretches and code spans break runs;
 * code spans render raw (they carry their own markdown theme styling). If
 * anchor matching failed, everything renders plain.
 */
function renderOpen(seg: Stretch, state: RenderState): string {
	const items = flattenItems(seg.long!);
	const anchors = anchorIndices(seg.short, items);
	let out = "";
	let runKind: "anchor" | "added" | "plain" | null = null;
	let run = "";
	const flush = () => {
		if (runKind === "anchor" && anchors !== null) out += state.style.closed(run);
		else if (runKind === "added") out += state.style.added(run);
		else out += run;
		run = "";
		runKind = null;
	};
	items.forEach((item, i) => {
		if (item.type === "stretch") {
			flush();
			out += renderSegment(item.stretch, state);
			return;
		}
		if (item.type === "code") {
			// Raw, outside any style run — pi's code theme owns its look.
			flush();
			out += item.text;
			return;
		}
		if (item.type === "sep") {
			// Whitespace rides inside the current run, keeping the underline whole.
			if (runKind !== null) run += item.text;
			else out += item.text;
			return;
		}
		const kind: "anchor" | "added" | "plain" =
			anchors === null ? "plain" : anchors.has(i) ? "anchor" : "added";
		if (kind !== runKind) flush();
		runKind = kind;
		run += item.text;
	});
	flush();
	return out;
}

/** Apply `wrap` to the trimmed text, keeping surrounding whitespace outside. */
function wrapPreservingSpaces(text: string, wrap: (t: string) => string): string {
	const m = text.match(/^(\s*)(\S[\s\S]*\S|\S)(\s*)$/);
	if (!m) return text;
	return `${m[1]}${wrap(m[2])}${m[3]}`;
}
