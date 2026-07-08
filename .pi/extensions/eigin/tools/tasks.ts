/**
 * add_tasks / resolve_tasks — a lightweight, agent-managed checklist.
 *
 * The task list is rendered alongside the current stage's instructions on
 * every turn (see workflow/stage-hint.ts and index.ts's `context` handler),
 * so it acts as the agent's own working memory during long-running or
 * multi-step jobs: add items as the plan of action becomes clear, resolve
 * them as they're done, and the list persists across turns (and session
 * resume) without the agent needing to re-derive or re-state it.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { formatTaskList, type Task, type TaskListState } from "../workflow/task-list.ts";

export const ADD_TASKS_TOOL = "add_tasks";
export const RESOLVE_TASKS_TOOL = "resolve_tasks";
export const CLEAR_TASKS_TOOL = "clear_tasks";

/** Read/write access to the task list, owned by the extension. */
export interface TaskListController {
	add(texts: string[], ctx: ExtensionContext): { added: Task[]; state: TaskListState };
	resolve(
		ids: number[],
		ctx: ExtensionContext,
	): { resolved: number[]; missing: number[]; state: TaskListState };
	clear(ctx: ExtensionContext): { state: TaskListState };
}

export function registerTaskTools(pi: ExtensionAPI, controller: TaskListController): void {
	pi.registerTool({
		name: ADD_TASKS_TOOL,
		label: "Add Tasks",
		description:
			"Add one or more tasks to the persistent task list. The list is shown alongside the current stage's " +
			"instructions on every turn until each task is resolved, so use it to track a checklist during " +
			"long-running or multi-step work instead of relying on memory.",
		promptSnippet: "Add tasks to the persistent task list (shown with stage instructions each turn)",
		promptGuidelines: [
			"Use add_tasks to write down a checklist at the start of multi-step or long-running work, and resolve_tasks to check items off as they're actually completed.",
		],
		parameters: Type.Object({
			tasks: Type.Array(Type.String({ minLength: 1 }), { minItems: 1 }),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx) {
			const { added, state } = controller.add(params.tasks as string[], ctx);
			if (added.length === 0) {
				return { content: [{ type: "text", text: "No tasks added (all entries were blank)." }] };
			}
			const addedLines = added.map((t) => `${t.id}. ${t.text}`).join("\n");
			return {
				content: [{ type: "text", text: `Added:\n${addedLines}\n\n${formatTaskList(state)}` }],
				details: { added, state },
			};
		},
	});

	pi.registerTool({
		name: RESOLVE_TASKS_TOOL,
		label: "Resolve Tasks",
		description:
			"Mark one or more tasks in the task list as done, by id. Resolved tasks stay visible (checked off) so " +
			"the list keeps a record of what's been completed during this piece of work.",
		promptSnippet: "Mark tasks in the persistent task list as done, by id",
		promptGuidelines: [
			"Use resolve_tasks to check off tasks by id once they're actually completed, not just started.",
		],
		parameters: Type.Object({
			ids: Type.Array(Type.Integer(), { minItems: 1 }),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx) {
			const { resolved, missing, state } = controller.resolve(params.ids as number[], ctx);
			const missingNote = missing.length > 0 ? `\nNo task with id(s): ${missing.join(", ")}.` : "";
			const list = formatTaskList(state) ?? "Task list is empty.";
			return {
				content: [{ type: "text", text: `Resolved: ${resolved.join(", ") || "none"}.${missingNote}\n\n${list}` }],
				details: { resolved, missing, state },
			};
		},
	});

	pi.registerTool({
		name: CLEAR_TASKS_TOOL,
		label: "Clear Tasks",
		description:
			"Remove every task from the task list, starting fresh. Use when the current checklist is done or no " +
			"longer relevant, e.g. before starting a new, unrelated piece of work.",
		promptSnippet: "Clear the persistent task list, removing all tasks",
		promptGuidelines: [
			"Use clear_tasks to reset the checklist once its tasks are all done or no longer relevant, rather than letting it accumulate stale entries.",
		],
		parameters: Type.Object({}),
		async execute(_id, _params, _signal, _onUpdate, ctx) {
			const { state } = controller.clear(ctx);
			return {
				content: [{ type: "text", text: "Task list cleared." }],
				details: { state },
			};
		},
	});
}
