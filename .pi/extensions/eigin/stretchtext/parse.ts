/**
 * Stretchtext markup parser: `{{short|long}}` with nesting inside long forms.
 * Ported from cc-stretch's hooks/parse.ts (MIT, github.com/pro-vi/cc-stretch),
 * simplified for pi: no streaming display filter, no paragraph splitting.
 *
 * - `{{text}}` with no `|` is legal: renders as plain text, nothing to open.
 * - Braces inside code spans and fenced code blocks are never markup.
 * - An unterminated stretch (still streaming) renders as its short form.
 * - A short form containing a newline is not openable; it renders fully open.
 */

export interface Stretch {
	/** Trimmed short form, namespaced by parent key with ' › ', siblings deduped ~2, ~3. */
	key: string;
	short: string;
	/** Undefined when no `|` was written. */
	long: Segment[] | undefined;
	/** False while the closing `}}` has not arrived (streaming). */
	terminated: boolean;
}

/**
 * An inline code span, copied verbatim (`backticks` included). Carried as its
 * own segment so rendering can break style runs around it — pi's Markdown
 * re-styles code spans with the code theme, whose reset would otherwise wipe
 * the surrounding stretch styling (see render.ts).
 */
export interface CodeSpan {
	text: string;
}

export type Segment = string | Stretch | CodeSpan;

export const KEY_SEPARATOR = " › ";

export function isStretch(segment: Segment): segment is Stretch {
	return typeof segment === "object" && "short" in segment;
}

export function isCode(segment: Segment): segment is CodeSpan {
	return typeof segment === "object" && "text" in segment;
}

/** A stretch the reader can open: syntactically complete, has a long form, one-line short. */
export function isOpenable(stretch: Stretch): boolean {
	return stretch.terminated && stretch.long !== undefined && !stretch.short.includes("\n");
}

/** All openable stretches, pre-order (parents before nested children). */
export function collectOpenable(segments: Segment[]): Stretch[] {
	const out: Stretch[] = [];
	const walk = (segs: Segment[]) => {
		for (const seg of segs) {
			if (!isStretch(seg)) continue;
			if (isOpenable(seg)) out.push(seg);
			if (seg.long) walk(seg.long);
		}
	};
	walk(segments);
	return out;
}

export function hasStretch(segments: Segment[]): boolean {
	return segments.some(isStretch);
}

interface Frame {
	stretch: Stretch;
	inShort: boolean;
	/** Short-form base counts among this frame's children, for ~2/~3 dedupe. */
	siblings: Map<string, number>;
}

export function parse(text: string): Segment[] {
	const root: Segment[] = [];
	const frames: Frame[] = [];
	const rootSiblings = new Map<string, number>();

	const innermost = (): Frame | undefined => frames[frames.length - 1];

	/** Segments array new content goes to: innermost long form, or root. */
	const target = (): Segment[] => {
		const f = innermost();
		return f && !f.inShort && f.stretch.long ? f.stretch.long : root;
	};

	const pushText = (s: string, asCode = false) => {
		if (!s) return;
		const f = innermost();
		if (f?.inShort) {
			f.stretch.short += s;
			return;
		}
		const arr = target();
		if (asCode) {
			arr.push({ text: s });
			return;
		}
		const lastEl = arr[arr.length - 1];
		if (typeof lastEl === "string") arr[arr.length - 1] = lastEl + s;
		else arr.push(s);
	};

	const assignKey = (stretch: Stretch) => {
		const parent = frames[frames.length - 2];
		const sibMap = parent ? parent.siblings : rootSiblings;
		const base = stretch.short.trim().replace(/\n/g, "↵");
		const count = sibMap.get(base) ?? 0;
		sibMap.set(base, count + 1);
		const suffix = count > 0 ? `~${count + 1}` : "";
		const prefix = parent ? parent.stretch.key + KEY_SEPARATOR : "";
		stretch.key = prefix + base + suffix;
	};

	const atLineStart = (i: number) => i === 0 || text[i - 1] === "\n";

	let i = 0;
	while (i < text.length) {
		// Fenced code block at line start: copy verbatim through the closing fence.
		if (atLineStart(i) && (text.startsWith("```", i) || text.startsWith("~~~", i))) {
			const marker = text.slice(i, i + 3);
			const close = text.indexOf(`\n${marker}`, i + 3);
			const end = close === -1 ? text.length : close + 1 + 3;
			pushText(text.slice(i, end));
			i = end;
			continue;
		}

		// Inline code span: copy verbatim through the matching backtick run, as
		// its own segment so render can break style runs around it.
		if (text[i] === "`") {
			let n = 0;
			while (text[i + n] === "`") n++;
			const run = "`".repeat(n);
			const close = text.indexOf(run, i + n);
			const end = close === -1 ? text.length : close + n;
			pushText(text.slice(i, end), true);
			i = end;
			continue;
		}

		if (text.startsWith("{{", i)) {
			const f = innermost();
			if (f?.inShort) {
				// No nesting inside a short form — literal braces.
				pushText("{{");
				i += 2;
				continue;
			}
			const stretch: Stretch = { key: "", short: "", long: undefined, terminated: false };
			target().push(stretch);
			frames.push({ stretch, inShort: true, siblings: new Map() });
			i += 2;
			continue;
		}

		if (text[i] === "|" && innermost()?.inShort) {
			const f = innermost()!;
			f.inShort = false;
			f.stretch.long = [];
			assignKey(f.stretch);
			i++;
			continue;
		}

		if (text.startsWith("}}", i) && frames.length > 0) {
			frames.pop()!.stretch.terminated = true;
			i += 2;
			continue;
		}

		pushText(text[i]);
		i++;
	}

	return root;
}
