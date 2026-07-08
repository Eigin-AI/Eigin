/**
 * Task list state — a simple in-session checklist the agent maintains for
 * itself. Rendered alongside the per-turn stage hint (see
 * workflow/stage-hint.ts and index.ts's `context` handler) rather than the
 * system prompt, for the same cache-locality reason stage guidance lives
 * there: the list changes turn to turn, so appending it to the always-fresh
 * last message costs nothing relative to not having it, while putting it in
 * the system prompt would invalidate the cached prefix on every change.
 *
 * Purpose: keep a long-running, multi-step job from losing track of what it
 * set out to do and what's already done.
 */

export interface Task {
	id: number;
	text: string;
	done: boolean;
}

export interface TaskListState {
	tasks: Task[];
	nextId: number;
}

export function emptyTaskList(): TaskListState {
	return { tasks: [], nextId: 1 };
}

/** Add one or more tasks, ignoring blank entries. */
export function addTasks(state: TaskListState, texts: string[]): { state: TaskListState; added: Task[] } {
	const added: Task[] = [];
	let id = state.nextId;
	for (const raw of texts) {
		const text = raw.trim();
		if (!text) continue;
		added.push({ id, text, done: false });
		id++;
	}
	return { state: { tasks: [...state.tasks, ...added], nextId: id }, added };
}

/**
 * Mark tasks done by id. Resolved tasks stay in the list (checked off, not
 * removed) so it keeps a record of what's been completed during the job.
 * Returns which ids were found vs. unknown.
 */
export function resolveTasks(
	state: TaskListState,
	ids: number[],
): { state: TaskListState; resolved: number[]; missing: number[] } {
	const idSet = new Set(ids);
	const found = new Set<number>();
	const tasks = state.tasks.map((t) => {
		if (!idSet.has(t.id)) return t;
		found.add(t.id);
		return { ...t, done: true };
	});
	const missing = ids.filter((id) => !found.has(id));
	return { state: { ...state, tasks }, resolved: [...found], missing };
}

/** Render the task list as a checklist block, or `null` when there are no tasks yet. */
export function formatTaskList(state: TaskListState): string | null {
	if (state.tasks.length === 0) return null;
	const lines = state.tasks.map((t) => `${t.done ? "[x]" : "[ ]"} ${t.id}. ${t.text}`);
	return `Task list:\n${lines.join("\n")}`;
}

/** Short "done/total" summary for the footer status. */
export function summarizeTaskList(state: TaskListState): string | null {
	if (state.tasks.length === 0) return null;
	const done = state.tasks.filter((t) => t.done).length;
	return `✅ ${done}/${state.tasks.length}`;
}

/** Remove every task, starting fresh. */
export function clearTasks(state: TaskListState): TaskListState {
	return { ...state, tasks: [] };
}
