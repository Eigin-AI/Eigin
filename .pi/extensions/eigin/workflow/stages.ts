/**
 * Stage vocabulary shared across workflows: context, plan, build, iterate,
 * test, merge.
 *
 * (There is no `review` stage: code review happens on the GitLab MR during
 * the Merge stage — see workflow/workflows.ts.)
 *
 * A *stage* is a mode the agent operates in (read-only exploration, plan
 * writing, implementing, etc). Its metadata — label, whether edit
 * tools are enabled, which model role it suggests — is stable no matter
 * which workflow is using it. Its *guidance* (the behavior-shaping text
 * injected into the system prompt) is not: a workflow tunes it to its own
 * purpose (see workflow/workflows.ts, which composes StageDefs from this
 * catalog plus per-workflow guidance).
 */

import type { RoleId } from "./roles.ts";

export type StageId =
  | "context"
  | "plan"
  | "build"
  | "iterate"
  | "test"
  | "merge";

/** Metadata for a stage that never varies by workflow. */
export interface StageMeta {
  id: StageId;
  label: string;
  /** Whether built-in edit/write tools are enabled in this stage. */
  allowsEdits: boolean;
  /**
   * Model role suggested when entering this stage (agent asks; you may
   * decline). The actual model behind a role is configurable — see
   * workflow/roles.ts and the /eigin:role command — so this points at a purpose
   * ("the planner model"), not a specific model.
   */
  role?: RoleId;
}

/** A stage as used by a specific workflow: metadata plus tuned guidance. */
export interface StageDef extends StageMeta {
  /** Short behavior-shaping guidance injected into the system prompt. */
  guidance: string;
}

export const STAGE_META: Record<StageId, StageMeta> = {
  context: { id: "context", label: "Context", allowsEdits: false, role: "planner" },
  plan: { id: "plan", label: "Plan", allowsEdits: true, role: "planner" }, // Restricted to markdown files by guard.
  build: { id: "build", label: "Build", allowsEdits: true, role: "builder" },
  iterate: { id: "iterate", label: "Iterate", allowsEdits: true, role: "builder" },
  test: { id: "test", label: "Test", allowsEdits: true, role: "builder" },
  merge: { id: "merge", label: "Merge", allowsEdits: true, role: "builder" },
};

/** Merge a stage's fixed metadata with workflow-specific guidance. */
export function stage(id: StageId, guidance: string): StageDef {
  return { ...STAGE_META[id], guidance };
}

export function isStageId(value: string): value is StageId {
  return value in STAGE_META;
}
