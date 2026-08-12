/**
 * Active-plan tracking — which `.pi/plans/*.md` file is the live plan, and
 * what the agent last saw of it.
 *
 * The collaborative-plan flow (see index.ts's `context` handler) re-reads the
 * active plan file from disk every turn and injects it, plus a diff of what
 * changed since the agent last saw it — so the user can edit the file
 * directly and have their changes picked up without flagging them.
 *
 * Pure/IO-free by design (file reads + persistence live in index.ts) so it's
 * plain-node testable. Only the file *path* is persisted across resume; the
 * last-seen content is in-memory, so the first turn after resume injects the
 * plan fresh with no diff, which is exactly right.
 */

export interface ActivePlanState {
	/** The live plan file, or null when none is active yet. */
	path: string | null;
	/** The file content the agent last had injected, for diffing. In-memory only. */
	lastSeenContent: string | null;
}

export function noActivePlan(): ActivePlanState {
	return { path: null, lastSeenContent: null };
}

/**
 * Set (or switch) the active plan file. Switching to a different path clears
 * the last-seen content so the new file is injected fresh rather than diffed
 * against the old one.
 */
export function setActivePlan(state: ActivePlanState, path: string): ActivePlanState {
	if (state.path === path) return state;
	return { path, lastSeenContent: null };
}

/** Record the content just injected, so the next turn can diff against it. */
export function markSeen(state: ActivePlanState, content: string): ActivePlanState {
	return { ...state, lastSeenContent: content };
}

/** Whether the current content differs from what the agent last saw. */
export function changedSinceSeen(state: ActivePlanState, current: string): boolean {
	return state.lastSeenContent !== null && state.lastSeenContent !== current;
}

/**
 * A compact line diff (`-` removed, `+` added) between the last-seen content
 * and the current content, or null when nothing changed or nothing was seen
 * yet (first injection). Built on a standard LCS so unchanged lines are
 * dropped and only the edited regions surface.
 */
export function diffSinceSeen(state: ActivePlanState, current: string): string | null {
	if (state.lastSeenContent === null || state.lastSeenContent === current) return null;
	return lineDiff(state.lastSeenContent, current);
}

/** LCS-based line diff. Returns `-`/`+`/` ` prefixed lines, changed regions only. */
export function lineDiff(oldText: string, newText: string): string {
	const a = oldText.split("\n");
	const b = newText.split("\n");
	const n = a.length;
	const m = b.length;

	// LCS length table.
	const lcs: number[][] = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));
	for (let i = n - 1; i >= 0; i--) {
		for (let j = m - 1; j >= 0; j--) {
			lcs[i][j] = a[i] === b[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
		}
	}

	const out: string[] = [];
	let i = 0;
	let j = 0;
	while (i < n && j < m) {
		if (a[i] === b[j]) {
			i++;
			j++;
		} else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
			out.push(`- ${a[i]}`);
			i++;
		} else {
			out.push(`+ ${b[j]}`);
			j++;
		}
	}
	while (i < n) out.push(`- ${a[i++]}`);
	while (j < m) out.push(`+ ${b[j++]}`);

	return out.join("\n");
}
