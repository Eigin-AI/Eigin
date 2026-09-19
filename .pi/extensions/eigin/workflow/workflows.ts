/**
 * Workflow definitions: named, ordered subsets of the stage vocabulary
 * (workflow/stages.ts).
 *
 * A workflow is not just "which stages" but "what does each stage mean here":
 * Feature-context asks "why does this need to exist"; Bug-context asks "how
 * do you reproduce this". Same stage id, different job. That per-workflow
 * meaning lives in `.pi/guidance/<workflow>/<stage>.md` (see guidance.ts), not
 * here — this file is only the sequences.
 *
 *   Feature   — context → plan → build → merge
 *   Bug       — context → plan → build → merge (plan is skippable)
 *   Prototype — context → iterate → merge
 *   Release   — context → plan → build → test → merge
 *   Ops       — ops (the default: single stage, no sequence; its behavior
 *               lives in .pi/guidance/ops/ops.md)
 *
 * Verification before Merge lives in Build's done-criteria (tests pass, it
 * compiles); Release keeps a dedicated Test stage because a release bump is
 * the one change worth verifying as its own step.
 *
 * Plan review is collaborative (co-edit a markdown file, no separate UI); code
 * review happens on the GitLab MR during the Merge stage. There is no distinct
 * `review` stage.
 */

import { STAGE_META, type StageId, type StageMeta } from "./stages.ts";

export type WorkflowId = "ops" | "feature" | "bug" | "prototype" | "release";

export interface WorkflowDef {
	id: WorkflowId;
	label: string;
	icon: string;
	/** Short (few-word) summary shown as a muted second line in the workflow picker. */
	summary: string;
	/** Ordered stages; guidance for each is loaded from `.pi/guidance/`. */
	stages: StageMeta[];
}

function sequence(...ids: StageId[]): StageMeta[] {
	return ids.map((id) => STAGE_META[id]);
}

const FEATURE: WorkflowDef = {
	id: "feature",
	label: "Feature",
	icon: "🧰",
	summary: "Careful planning, implementation, and MR review.",
	stages: sequence("context", "plan", "build", "merge"),
};

const BUG: WorkflowDef = {
	id: "bug",
	label: "Bug",
	icon: "🐞",
	summary: "Quick context, implementation, and testing.",
	stages: sequence("context", "plan", "build", "merge"),
};

const PROTOTYPE: WorkflowDef = {
	id: "prototype",
	label: "Prototype",
	icon: "🧬",
	summary: "Quick context, then iterate together with no upfront plan.",
	stages: sequence("context", "iterate", "merge"),
};

const RELEASE: WorkflowDef = {
	id: "release",
	label: "Release",
	icon: "🚀",
	summary: "Bump version, regenerate changelog, prep the release.",
	stages: sequence("context", "plan", "build", "test", "merge"),
};

const OPS: WorkflowDef = {
	id: "ops",
	label: "Ops",
	icon: "⚙️",
	summary: "Free-form: issues, chores, orchestration. Work directly, no stages.",
	stages: sequence("ops"),
};

// Ops first: it's the default and the picker's top choice.
export const WORKFLOWS: WorkflowDef[] = [OPS, FEATURE, BUG, PROTOTYPE, RELEASE];

export function getWorkflow(id: WorkflowId): WorkflowDef {
	const workflow = WORKFLOWS.find((w) => w.id === id);
	if (!workflow) throw new Error(`Unknown workflow: ${id}`);
	return workflow;
}

export function isWorkflowId(value: string): value is WorkflowId {
	return WORKFLOWS.some((w) => w.id === value);
}

/** The stage a workflow starts on. */
export function firstStage(workflow: WorkflowDef): StageId {
	return workflow.stages[0].id;
}

export function hasStage(workflow: WorkflowDef, id: StageId): boolean {
	return workflow.stages.some((s) => s.id === id);
}

/** Look up a stage within a workflow's sequence. */
export function getStageInWorkflow(workflow: WorkflowDef, id: StageId): StageMeta {
	const found = workflow.stages.find((s) => s.id === id);
	if (!found) throw new Error(`Stage "${id}" is not part of the ${workflow.label} workflow`);
	return found;
}

export function stageIndexIn(workflow: WorkflowDef, id: StageId): number {
	return workflow.stages.findIndex((s) => s.id === id);
}

/** Step relative to a stage within a workflow, clamped to its sequence bounds. */
export function relativeStageIn(workflow: WorkflowDef, id: StageId, delta: number): StageMeta {
	const i = stageIndexIn(workflow, id);
	const next = Math.max(0, Math.min(workflow.stages.length - 1, i + delta));
	return workflow.stages[next];
}
