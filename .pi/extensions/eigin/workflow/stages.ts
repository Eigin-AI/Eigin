/**
 * Stage vocabulary shared across workflows: context, plan, build, iterate,
 * test, merge, ops. Not every workflow uses every stage — Feature and Bug sit
 * out iterate and test; Release keeps the only Test stage; Ops is a single
 * stage: no sequence at all, just direct work.
 *
 * (There is no `review` stage: code review happens on the GitLab MR during
 * the Merge stage — see workflow/workflows.ts.)
 *
 * A *stage* is a mode the agent operates in (read-only exploration, plan
 * writing, implementing, etc). Its metadata — label, whether edit
 * tools are enabled, which model role it suggests — is stable no matter
 * which workflow is using it. Its *guidance* (the behavior-shaping text
 * injected per turn) is not: each workflow tunes it in
 * `.pi/guidance/<workflow>/<stage>.md`, loaded by workflow/guidance.ts.
 */

import type { RoleId } from "./roles.ts";

export type StageId =
  | "context"
  | "plan"
  | "build"
  | "iterate"
  | "test"
  | "merge"
  | "ops";

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

export const STAGE_META: Record<StageId, StageMeta> = {
  context: { id: "context", label: "Context", allowsEdits: false, role: "planner" },
  plan: { id: "plan", label: "Plan", allowsEdits: true, role: "planner" }, // Restricted to markdown files by guard.
  build: { id: "build", label: "Build", allowsEdits: true, role: "builder" },
  iterate: { id: "iterate", label: "Iterate", allowsEdits: true, role: "builder" },
  test: { id: "test", label: "Test", allowsEdits: true, role: "builder" },
  merge: { id: "merge", label: "Merge", allowsEdits: true, role: "builder" },
  ops: { id: "ops", label: "Ops", allowsEdits: true, role: "builder" },
};

export function isStageId(value: string): value is StageId {
  return value in STAGE_META;
}
