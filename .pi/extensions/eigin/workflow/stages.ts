/**
 * Stage definitions for the workflow pipeline:
 *   context → plan → build → iterate → review → merge
 *
 * Each stage shapes how the agent behaves, which tools are available, and
 * which model *role* it suggests (see workflow/roles.ts for what model is
 * actually behind that role). Edit this file to tune the workflow.
 */

import type { RoleId } from "./roles.ts";

export type StageId =
  | "context"
  | "plan"
  | "build"
  | "iterate"
  | "review"
  | "merge";

export interface StageDef {
  id: StageId;
  label: string;
  icon: string;
  /** Whether built-in edit/write tools are enabled in this stage. */
  allowsEdits: boolean;
  /**
   * Model role suggested when entering this stage (agent asks; you may
   * decline). The actual model behind a role is configurable — see
   * workflow/roles.ts and the /role command — so this points at a purpose
   * ("the planner model"), not a specific model.
   */
  role?: RoleId;
  /** Short behavior-shaping guidance injected into the system prompt. */
  guidance: string;
}

export const STAGES: StageDef[] = [
  {
    id: "context",
    label: "Context",
    icon: "🔍",
    allowsEdits: false,
    role: "planner",
    guidance: `You are in the Context stage: read-only, conversational.
Goal: build shared understanding of the problem, not the solution.
- Draw out the *why*: what need/ask/problem is this, where did it come from, what does it contribute to the product?
- Treat the user's ideas as suggestions, not prescriptions. Explore them.
- For bigger asks, help decompose into smaller, individually-verifiable pieces.
- Do NOT write code or produce an implementation plan yet. Load and organize context.
- Ask questions when something is unclear. Stay product-minded: aim for a great product, prefer simple over clever.
- When you have a few concrete, structured clarifying questions (e.g. multiple-choice decisions about scope or direction), prefer the ask_questions tool over prose Q&A.
- Look up the originating GitLab issue with the \`glab\` CLI or a web fetch (project: dev/eigin on code.eigin.ai, e.g. \`glab issue view <number> --output json\`) and ground the discussion in what's already captured there.
- If no issue exists for this work, suggest creating one. If the work might span multiple separate pieces, suggest one issue per piece — each with a clear description of the problem and what it's solving. Check existing issues/labels (\`glab label list\`) for the right tags to apply, following the conventions in \`.gitlab/issue_templates/\`.`,
  },
  {
    id: "plan",
    label: "Plan",
    icon: "📝",
    allowsEdits: true, // Restricted to markdown files by guard
    role: "planner",
    guidance: `You are in the Plan stage: markdown-writable, an interview that narrows the funnel.
Goal: a *tactical* implementation plan, not a spec.
- Interview the user: ask specific, clarifying questions about technical scope, constraints, and approach. Narrow toward something concrete enough to implement.
- This is the funnel-narrowing interview — lean on the ask_questions tool for concrete decision points (options, trade-offs, scope calls). It's built for exactly this: structured questions with a recommended default, rather than a wall of prose questions.
- Then produce a technical plan: brief context + direction, then mostly specifics (key components, things that must be done a certain way). Not every line of code.
- Iterate on the plan with the user's comments/corrections. Push back when you disagree — it's collaborative.
- Write plans to \`.pi/plans/<short-name>.md\`, then submit with the submit_plan tool.
- The user must explicitly approve before moving to the Build stage. Do not start building.`,
  },
  {
    id: "build",
    label: "Build",
    icon: "🔨",
    allowsEdits: true,
    role: "builder",
    guidance: `You are in the Build stage: edits enabled, mostly autonomous.
Goal: implement the approved plan.
- Follow the approved plan and the project's architectural guidelines.
- Make it verifiable: add unit/integration tests where feasible; build and test as you go.
- Keep the run focused (~5–15 min of work). Don't over-scope; small spec errors spiral.
- Done when: built roughly to spec, has some test coverage, and it compiles.`,
  },
  {
    id: "iterate",
    label: "Iterate",
    icon: "🔁",
    allowsEdits: true,
    role: "builder",
    guidance: `You are in the Iterate stage: edits enabled, fast, human-in-the-loop.
Goal: revisit the build with a concrete product in hand — shape it with the user.
- The first iteration exists now. Trying it may change what it should be or do; make the changes and edits that have become apparent now that it's built.
- Make small/medium changes quickly and correctly, with good practice. The user is trying the product right now.
- Avoid expensive rebuilds (e.g. iOS builds to device) — the user verifies — but cheap verification (e.g. cargo test) is fine. Don't rebuild/retest constantly just to confirm.`,
  },
  {
    id: "review",
    label: "Review",
    icon: "👀",
    allowsEdits: true,
    role: "builder",
    guidance: `You are in the Review stage: code-level review and fixes.
Behavior/functionality is settled — now make the *code* good.
- Walk the code with the user. Expect "why is this this way?", "bundle these?", "unclear name", "reads weird", "missing docs".
- Apply corrections from feedback. Push back when the user is wrong — figure it out together.
- Keep changes surgical and well-documented per project conventions.`,
  },
  {
    id: "merge",
    label: "Merge",
    icon: "🔀",
    allowsEdits: true,
    role: "builder",
    guidance: `You are in the Merge stage: prepare the merge request.
- Draft a short, concrete MR description (not prose): what it is, what it does, key decisions, what to watch out for.
- Reference the originating issue. If none exists, note that one should be created.
- Confirm with the user that the branch has been pushed (do NOT run git yourself — the user drives git and pushes themselves).
- Once pushed, use the \`glab\` CLI to create the merge request (project: dev/eigin on code.eigin.ai), e.g. \`glab mr create --title "..." --description-file <path> --source-branch <branch>\`.
- Title the MR using Conventional Commits (e.g. \`feat: pi coding agent\`, \`fix: deal with local model crash\`) — type, colon, short imperative summary.
- Check existing issues/labels (\`glab label list\`) for the right tags to apply to the MR, following the conventions in \`.gitlab/issue_templates/\`.`,
  },
];

export function getStage(id: StageId): StageDef {
  const stage = STAGES.find((s) => s.id === id);
  if (!stage) throw new Error(`Unknown stage: ${id}`);
  return stage;
}

export function isStageId(value: string): value is StageId {
  return STAGES.some((s) => s.id === value);
}

export function stageIndex(id: StageId): number {
  return STAGES.findIndex((s) => s.id === id);
}

/** Step relative to a stage, clamped to the pipeline bounds. */
export function relativeStage(id: StageId, delta: number): StageDef {
  const i = stageIndex(id);
  const next = Math.max(0, Math.min(STAGES.length - 1, i + delta));
  return STAGES[next];
}
