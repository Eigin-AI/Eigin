/**
 * Workflow definitions: named, ordered subsets of the stage vocabulary
 * (workflow/stages.ts), each with guidance tuned to that workflow's purpose.
 *
 * A workflow is not just "which stages" but "what does each stage mean here":
 * Feature-context asks "why does this need to exist"; Bug-context asks "how
 * do you reproduce this". Same stage id, different job.
 *
 *   Feature   — context → plan → build → iterate → review → merge
 *   Bug       — context → plan → build → test → merge (plan is skippable)
 *   Prototype — context → iterate → merge
 */

import { stage, type StageDef, type StageId } from "./stages.ts";

export type WorkflowId = "feature" | "bug" | "prototype";

export interface WorkflowDef {
  id: WorkflowId;
  label: string;
  icon: string;
  /** Short (few-word) summary shown as a muted second line in the workflow picker. */
  summary: string;
  /** Ordered stages, each carrying guidance tuned to this workflow. */
  stages: StageDef[];
}

const FEATURE: WorkflowDef = {
  id: "feature",
  label: "Feature",
  icon: "🧰",
  summary: "Careful planning, implementation, iteration, and review.",
  stages: [
    stage(
      "context",
      `You are in the Context stage: read-only, conversational.
Goal: build shared understanding of the problem, not the solution.
- Draw out the *why*: what need/ask/problem is this, where did it come from, what does it contribute to the product?
- Treat the user's ideas as suggestions, not prescriptions. Explore them.
- For bigger asks, help decompose into smaller, individually-verifiable pieces.
- Do NOT write code or produce an implementation plan yet. Load and organize context.
- Ask questions when something is unclear. Stay product-minded: aim for a great product, prefer simple over clever.
- When you have a few concrete, structured clarifying questions (e.g. multiple-choice decisions about scope or direction), prefer the ask_questions tool over prose Q&A.
- Delegate codebase/docs/web reconnaissance to the explore sub-agent rather than digging through files inline — keep this stage a focused conversation, not a solo research session.
- Look up the originating GitLab issue with the \`glab\` CLI or a web fetch (project: dev/eigin on code.eigin.ai, e.g. \`glab issue view <number> --output json\`) and ground the discussion in what's already captured there.
- If no issue exists for this work, suggest creating one. If the work might span multiple separate pieces, suggest one issue per piece — each with a clear description of the problem and what it's solving. Check existing issues/labels (\`glab label list\`) for the right tags to apply, following the conventions in \`.gitlab/issue_templates/\`.`,
    ),
    stage(
      "plan",
      `You are in the Plan stage: markdown-writable, an interview that narrows the funnel.
Goal: a *tactical* implementation plan, not a spec.
- Interview the user: ask specific, clarifying questions about technical scope, constraints, and approach. Narrow toward something concrete enough to implement.
- This is the funnel-narrowing interview — lean on the ask_questions tool for concrete decision points (options, trade-offs, scope calls). It's built for exactly this: structured questions with a recommended default, rather than a wall of prose questions.
- Use the explore sub-agent for any codebase spelunking needed to firm up the approach (how something's currently structured, where a piece of logic lives) instead of doing that digging inline.
- Then produce a technical plan: brief context + direction, then mostly specifics (key components, things that must be done a certain way). Not every line of code.
- Iterate on the plan with the user's comments/corrections. Push back when you disagree — it's collaborative.
- Write plans to \`.pi/plans/<short-name>.md\`, then submit with the submit_plan tool.
- The user must explicitly approve before moving to the Build stage. Do not start building.`,
    ),
    stage(
      "build",
      `You are in the Build stage: edits enabled, mostly autonomous.
Goal: implement the approved plan.
- Follow the approved plan and the project's architectural guidelines.
- Make it verifiable: add unit/integration tests where feasible; build and test as you go.
- Keep the run focused (~5–15 min of work). Don't over-scope; small spec errors spiral.
- Done when: built roughly to spec, has some test coverage, and it compiles.`,
    ),
    stage(
      "iterate",
      `You are in the Iterate stage: edits enabled, fast, human-in-the-loop.
Goal: revisit the build with a concrete product in hand — shape it with the user.
- The first iteration exists now. Trying it may change what it should be or do; make the changes and edits that have become apparent now that it's built.
- Make small/medium changes quickly and correctly, with good practice. The user is trying the product right now.
- Avoid expensive rebuilds (e.g. iOS builds to device) — the user verifies — but cheap verification (e.g. cargo test) is fine. Don't rebuild/retest constantly just to confirm.`,
    ),
    stage(
      "review",
      `You are in the Review stage: code-level review and fixes.
Behavior/functionality is settled — now make the *code* good.
- Walk the code with the user. Expect "why is this this way?", "bundle these?", "unclear name", "reads weird", "missing docs".
- Apply corrections from feedback. Push back when the user is wrong — figure it out together.
- Keep changes surgical and well-documented per project conventions.`,
    ),
    stage(
      "merge",
      `You are in the Merge stage: prepare the merge request.
- Draft the MR description following \`.gitlab/merge_request_templates/Default.md\`: closes-issue line, one-line summary, then Summary / Changes / Related / Notes / How to Test. Keep it short and scannable, not prose — Changes is high-level bullet points of what's relevant, not every diff.
- Reference the originating issue via \`Closes #<n>\`. If none exists, note that one should be created.
- Confirm with the user that the branch has been pushed (do NOT run git yourself — the user drives git and pushes themselves).
- Write MR drafts to \`.pi/mr/<short-name>.md\`.
- Once pushed, use the \`glab\` CLI to create the merge request (project: dev/eigin on code.eigin.ai), e.g. \`glab mr create --title "..." --description "$(cat <path>)" --source-branch <branch>\` (glab's \`mr create\` has no \`--description-file\` flag — pass the rendered description text).
- Title the MR using Conventional Commits (e.g. \`feat: pi coding agent\`, \`fix: deal with local model crash\`) — type, colon, short imperative summary.
- Check existing issues/labels (\`glab label list\`) for the right tags to apply to the MR, following the conventions in \`.gitlab/issue_templates/\`.`,
    ),
  ],
};

const MERGE_GUIDANCE = FEATURE.stages.find((s) => s.id === "merge")!.guidance;

const BUG: WorkflowDef = {
  id: "bug",
  label: "Bug",
  icon: "🐞",
  summary: "Quick context, implementation, and testing.",
  stages: [
    stage(
      "context",
      `You are in the Context stage: read-only, conversational.
Goal: understand the bug well enough to reason about a fix.
- Describe what's happening vs. what should happen. Get specific: when does it occur, how would you reproduce it, is it consistent or intermittent?
- Surface current theories about what's wrong — what's the suspected cause, what's ruled out already?
- Ask about candidate fixes if any are already in mind, and what "fixed" looks like (which case must stop happening / start happening).
- Do NOT write code yet. This is diagnosis, not implementation.
- Ask clarifying questions when the repro or symptoms are unclear — prefer the ask_questions tool for concrete either/or decisions.
- Delegate tracing the suspected code path (and finding related tests) to the explore sub-agent rather than digging through files inline.
- Look up the originating GitLab issue with \`glab issue view <number> --output json\` (project: dev/eigin on code.eigin.ai) and ground the discussion in what's already reported there. If no issue exists, suggest creating one.`,
    ),
    stage(
      "plan",
      `You are in the Plan stage: markdown-writable, lightweight.
Goal: a small bug-fix proposal, not a spec — this stage is skippable when the fix is obvious.
- If the cause and fix are clear from Context, say so and propose moving straight to Build (propose_stage) instead of writing a plan.
- Otherwise, write a short proposal: suspected root cause, the fix, and anything risky or non-obvious about it. A few sentences to a short paragraph, not a document.
- Use ask_questions if there's a real fork in approach worth the user's call.
- Lean on the explore sub-agent for any code spelunking needed to firm up the fix approach, rather than doing it inline.
- Write to \`.pi/plans/<short-name>.md\` and submit with submit_plan only if the fix is non-trivial enough to warrant a look before touching code.
- The user must approve before moving to Build.`,
    ),
    stage(
      "build",
      `You are in the Build stage: edits enabled, mostly autonomous.
Goal: implement the fix.
- Follow the approved proposal (or Context discussion, if Plan was skipped).
- Add a test that reproduces the bug (failing before, passing after) where feasible, or update a stale test whose expectations no longer match the corrected behavior.
- Keep the change surgical — a bug fix, not a refactor. Don't expand scope beyond what's needed to resolve the reported issue.
- Done when: the fix is in, it compiles, and test coverage reflects the corrected behavior.`,
    ),
    stage(
      "test",
      `You are in the Test stage: edits enabled, verification-focused.
Goal: confirm the fix actually holds — the bug-flow analogue of Iterate, but about verifying rather than shaping.
- Run whatever cheap verification is available yourself (e.g. \`cargo test\`, unit/integration suites covering the area) and report what you checked.
- Make sure the case is covered by a test where feasible — add one now if Build didn't, or tighten it if it's too loose to actually catch a regression.
- The user does the human verification (reproducing the original symptom, confirming it's gone). Wait for their confirmation before moving to Merge.
- Small follow-up fixes are expected here if verification turns up something Build missed — keep them scoped to the bug.`,
    ),
    stage("merge", MERGE_GUIDANCE),
  ],
};

const PROTOTYPE: WorkflowDef = {
  id: "prototype",
  label: "Prototype",
  icon: "🧬",
  summary: "Quick context, then iterate together with no upfront plan.",
  stages: [
    stage(
      "context",
      `You are in the Context stage: read-only, conversational.
Goal: just enough shared understanding to start — this is a prototype, not a planned feature.
- Get the idea, the rough shape of what to try, and anything that would make an attempt clearly wrong (constraints, existing code it must fit into).
- Don't over-plan or decompose into a spec — that's not the point here. A sentence or two of direction is often enough.
- Ask only what's needed to start; prefer discovering the rest by trying it.
- Delegate any codebase/docs reconnaissance to the explore sub-agent rather than digging through files yourself, so this stays a quick conversation.`,
    ),
    stage(
      "iterate",
      `You are in the Iterate stage: edits enabled, fast, human-in-the-loop.
Goal: build and shape the idea one step at a time, together, from scratch.
- There's no plan and no build-stage handoff to lean on — start from the Context discussion and make something.
- Make small/medium changes quickly and correctly, with good practice. The user is trying things as you go.
- Avoid expensive rebuilds (e.g. iOS builds to device) — the user verifies — but cheap verification (e.g. cargo test) is fine. Don't rebuild/retest constantly just to confirm.
- Follow the user's lead on direction changes — prototypes are expected to move as ideas get tried.`,
    ),
    stage("merge", MERGE_GUIDANCE),
  ],
};

export const WORKFLOWS: WorkflowDef[] = [FEATURE, BUG, PROTOTYPE];

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

/** Look up a stage within a workflow's sequence (guidance tuned to that workflow). */
export function getStageInWorkflow(workflow: WorkflowDef, id: StageId): StageDef {
  const found = workflow.stages.find((s) => s.id === id);
  if (!found) throw new Error(`Stage "${id}" is not part of the ${workflow.label} workflow`);
  return found;
}

export function stageIndexIn(workflow: WorkflowDef, id: StageId): number {
  return workflow.stages.findIndex((s) => s.id === id);
}

/** Step relative to a stage within a workflow, clamped to its sequence bounds. */
export function relativeStageIn(workflow: WorkflowDef, id: StageId, delta: number): StageDef {
  const i = stageIndexIn(workflow, id);
  const next = Math.max(0, Math.min(workflow.stages.length - 1, i + delta));
  return workflow.stages[next];
}
