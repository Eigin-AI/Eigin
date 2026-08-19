/**
 * Workflow definitions: named, ordered subsets of the stage vocabulary
 * (workflow/stages.ts), each with guidance tuned to that workflow's purpose.
 *
 * A workflow is not just "which stages" but "what does each stage mean here":
 * Feature-context asks "why does this need to exist"; Bug-context asks "how
 * do you reproduce this". Same stage id, different job.
 *
 *   Feature   — context → plan → build → iterate → merge
 *   Bug       — context → plan → build → test → merge (plan is skippable)
 *   Prototype — context → iterate → merge
 *
 * Plan review is collaborative (co-edit a markdown file, no separate UI); code
 * review happens on the GitLab MR during the Merge stage. There is no distinct
 * `review` stage.
 */

import { stage, type StageDef, type StageId } from "./stages.ts";

export type WorkflowId = "feature" | "bug" | "prototype" | "release";

export interface WorkflowDef {
  id: WorkflowId;
  label: string;
  icon: string;
  /** Short (few-word) summary shown as a muted second line in the workflow picker. */
  summary: string;
  /** Ordered stages, each carrying guidance tuned to this workflow. */
  stages: StageDef[];
}

// Shared across all workflows: code review happens on the GitLab MR here in the
// Merge stage (there is no separate review stage). The comment loop uses
// wait_for_user + a paginated glab pull; see tools/wait-for-user.ts.
const MERGE_GUIDANCE = `You are in the Merge stage: open the MR and drive review to a merge.
Signpost briefly what you expect the user to do — keep the flow self-evident, not a manual.
- Confirm the branch is pushed. You never run git — the user pushes and merges.
- Draft a short MR description per \`.gitlab/merge_request_templates/Default.md\` (Summary / Changes / Related / Notes / How to Test; \`Closes #<n>\` if there's an issue). Short and scannable — bullets, not prose. Save to \`.pi/mr/<issue#>-<work-name>.md\` (e.g. \`162-auto-activating-skills.md\`; drop the issue# if none).
- Create the MR with the \`glab\` CLI (project: dev/eigin on code.eigin.ai), e.g. \`glab mr create --title "..." --description "$(cat <path>)" --source-branch <branch>\`. Title in Conventional Commits form (e.g. \`feat: ...\`). Check \`glab label list\` for the right tags.
- Write a SHORT review guide to \`.pi/mr/<issue#>-<work-name>-guide.md\` (git-ignored) and post it as an MR comment: what to review together, what matters most and why — files grouped by relationship, story order. Scannable, not exhaustive. Tell the user the guide's path.
- Then call wait_for_user (prompt "Review the MR and leave comments"; confirmLabel "Pull my comments") instead of explaining at length.
- When the user signals, pull unresolved comments — PAGINATE so none are missed: \`glab api projects/:id/merge_requests/:iid/discussions --paginate\` (get the iid via \`glab mr view --output json\` on the current branch). Turn actionable comments into tasks (add_tasks) so they stay in context.
- Fix what's directly fixable and resolve those threads (the user can reopen); answer questions in-thread via \`glab api ...merge_requests/:iid/discussions/:id/notes\`, prefixing replies with "**Agent**:". Summarize anything left in chat. Resolve each task as its thread is handled.
- Loop (wait_for_user → pull → address) until the user merges. You never merge.`;

const FEATURE: WorkflowDef = {
  id: "feature",
  label: "Feature",
  icon: "🧰",
  summary: "Careful planning, implementation, iteration, and MR review.",
  stages: [
    stage(
      "context",
      `You are in the Context stage: read-only, conversational.
Goal: build shared understanding of the problem, not the solution.
- Draw out the *why*: what need/ask/problem is this, where did it come from, what does it contribute to the product?
- Treat the user's ideas as suggestions, not prescriptions. Explore them.
- For bigger asks, help decompose into smaller, individually-verifiable pieces.
- Do NOT write code or produce a plan yet — no files. Get introduced to the problem and load context; the plan comes next stage.
- Ask questions when something is unclear. Stay product-minded: aim for a great product, prefer simple over clever.
- When you have a few concrete, structured clarifying questions (e.g. multiple-choice decisions about scope or direction), prefer the ask_questions tool over prose Q&A.
- Delegate codebase/docs/web reconnaissance to the explore sub-agent rather than digging through files inline — keep this stage a focused conversation, not a solo research session.
- Look up the originating GitLab issue with the \`glab\` CLI or a web fetch (project: dev/eigin on code.eigin.ai, e.g. \`glab issue view <number> --output json\`) and ground the discussion in what's already captured there.
- If no issue exists for this work, suggest creating one. If the work might span multiple separate pieces, suggest one issue per piece — each with a clear description of the problem and what it's solving. Check existing issues/labels (\`glab label list\`) for the right tags to apply, following the conventions in \`.gitlab/issue_templates/\`.`,
    ),
    stage(
      "plan",
      `You are in the Plan stage: co-editing a markdown plan with the user (markdown-writable).
Goal: a *tactical* implementation plan you both shape — not a doc you present.
- Interview to narrow scope: lean on the ask_questions tool for concrete decision points (options, trade-offs, scope calls) over a wall of prose questions.
- Use the explore sub-agent for codebase spelunking needed to firm up the approach, instead of digging inline.
- Write the plan to \`.pi/plans/<issue#>-<work-name>.md\` (e.g. \`162-auto-activating-skills.md\`; drop the issue# if there's no issue) using EXACTLY this layout, and keep it maintained every round:
    # Plan: <title>

    ## Summary
    2–4 lines, plain English: what this is and where it's going.

    ## The idea
    Plain English, no jargon: where we are now, where we're going, and the
    decisions/proposals on the table. Readable without knowing the code.

    ## Open questions
    Pinned here; anchor-link to sections (\`[label](#section)\`). Remove each as it's resolved.

    ## Implementation
    The technical side. Lead with shape, not prose: the key types, interfaces,
    and function signatures, plus high-level pseudocode / call flow. Show the
    logic and the contracts so the approach can be judged against The idea.

    ## Decision log
    Numbered list, one short line per round. Append an entry EVERY round — required, not optional.
- The two sides do different jobs: **The idea** is for judging intent (does this solve the right problem?), **Implementation** is for judging approach (does this design fit the intent?). Keep them distinct — don't let jargon leak up into The idea, or prose bloat the Implementation.
- Implementation should read like a sketch, not an essay — favour types and pseudocode over paragraphs. A simple one might look like:

    ## Implementation

    New type in \`relay/src/search.rs\`:
    \`\`\`rust
    struct SearchClient { base: Url, key: SecretString }

    impl SearchClient {
        // Err(Unavailable) => caller shows a fixed "search unavailable" message
        async fn query(&self, q: &str) -> Result<Vec<Hit>, SearchError>;
    }
    \`\`\`

    Call flow — \`handle_search(req)\`:
    - validate query, then \`client.query(q)\`
    - \`Ok(hits)\`        → 200 with results
    - \`Err(Unavailable)\` → 503, fixed message
    - \`Err(other)\`       → log internally, 500, fixed message

    Wiring: build one \`SearchClient\` at startup, share via app state.
- Keep prose SHORT — short lines, generous whitespace. No walls of text.
- It's collaborative: the file is re-read every turn, so you'll see the user's direct edits and free-typed notes as a diff — respond to them. Push back when you disagree.
- After a round of edits, don't explain at length: call wait_for_user (confirmLabel "Review my plan edits") to hand off for the next pass. Its prompt is about reviewing/editing THIS pass only — never mention advancing or moving to Build in it.
- When the user signals: strip their inline comments, address them, APPEND a Decision log entry, then hand back with wait_for_user again.
- Advancing is a SEPARATE step: only when the plan is fully formed and no comments are open, call propose_stage(build) on its own. Never bundle "move to build" into a wait_for_user prompt/label — that dialog is the approval. Don't ask too early; expect several rounds, and never advance on your own.`,
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
    stage("merge", MERGE_GUIDANCE),
  ],
};

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
      `You are in the Plan stage: a short, co-edited bug-fix proposal (skippable).
- If the cause and fix are clear from Context, say so and propose_stage(build) instead of writing a plan.
- Otherwise write a short proposal to \`.pi/plans/<issue#>-<work-name>.md\` (e.g. \`162-auto-activating-skills.md\`; drop the issue# if none): suspected root cause, the fix, anything risky. Short prose; short lines, generous whitespace.
- It's collaborative: the file is re-read each turn — respond to the user's direct edits and notes. After a round, call wait_for_user (about reviewing this pass only, never advancing) rather than explaining at length.
- Use ask_questions if there's a real fork in approach worth the user's call.
- Lean on the explore sub-agent for code spelunking needed to firm up the fix, rather than doing it inline.
- When the user signals: strip inline comments, address them, update the Decision log.
- Approve gate: propose_stage(build) only when fully formed with no open comments. The user's confirmation is the approval.`,
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

const RELEASE: WorkflowDef = {
  id: "release",
  label: "Release",
  icon: "🚀",
  summary: "Bump version, regenerate changelog, prep the release.",
  stages: [
    stage(
      "context",
      `You are in the Context stage: read-only, conversational.
Goal: figure out what's shipping and what the next version should be.
- Assume a release branch already exists and is checked out — the user creates it manually. Confirm with \`git branch --show-current\` and note it.
- Look at what changed since the last tag: \`git tag --list --sort=-v:refname\` for the last semantic tag, then \`git log <last-tag>..HEAD --oneline\`.
- Decide the version bump with the user: this project is pre-1.0, so bump minor (0.X.0) by default, or patch (0.X.Y) for a small fix-only release. Look at \`src/eigin_ios/project.yml\` for the current MARKETING_VERSION.
- Note any breaking changes or notable user-facing items worth calling out in release notes later.
- Do NOT edit any files yet — this stage is just grounding the decision.`,
    ),
    stage(
      "plan",
      `You are in the Plan stage: co-editing a short markdown release plan with the user (markdown-writable).
Goal: pin down the version and draft the release notes before touching any files.
- Write the plan to \`.pi/plans/release-<version>.md\` (e.g. \`release-0.16.0.md\`) using EXACTLY this layout:
    # Release: <version>

    ## Summary
    1-2 lines: what this release is (minor/patch), headline items.

    ## What's new
    Short bullets, user-facing framing — this becomes the GitLab release description.

    ## Breaking changes
    Bullets, or "None" if there aren't any.

    ## Decision log
    Numbered list, one short line per round.
- Keep it short — this drafts the GitLab release notes, not a changelog (git cliff generates that from commits in Build).
- It's collaborative: re-read every turn, respond to the user's direct edits. After a round, call wait_for_user (confirmLabel "Review my plan edits") rather than explaining at length.
- Approve gate: propose_stage(build) only when the version and release notes are settled and no comments are open. The user's confirmation is the approval.`,
    ),
    stage(
      "build",
      `You are in the Build stage: edits enabled, mostly autonomous.
Goal: bump the version and regenerate the changelog.
- Update \`MARKETING_VERSION\` in \`src/eigin_ios/project.yml\` to the agreed version — BOTH occurrences (the \`Eigin\` and \`EiginDev\` targets).
- Run \`git cliff --tag <version> --output CHANGELOG.md\` (check \`cliff.toml\` for exact invocation conventions) to regenerate the changelog from conventional commits.
- Read the regenerated CHANGELOG.md diff and hand-tune it if git cliff mis-grouped or mis-worded anything — don't just trust it blindly.
- Do not commit, tag, or push — that's the user's, in Merge.
- Done when: project.yml is bumped in both places, CHANGELOG.md is regenerated and looks right.`,
    ),
    stage(
      "test",
      `You are in the Test stage: edits enabled, verification-focused.
Goal: confirm the bump didn't break anything before it ships.
- Run \`just build\` and \`just test\` (or the relevant subset) yourself and report what you checked.
- Verify \`src/eigin_ios/project.yml\` parses and the version shows up right (e.g. \`just generate\` if the Xcode project needs regenerating from project.yml).
- Small fixups are expected here if verification turns up a typo or formatting issue in the changelog or version bump — keep them scoped to the release.
- The user does final manual verification (e.g. running the app). Wait for their go-ahead before Merge.`,
    ),
    stage(
      "merge",
      `You are in the Merge stage: prep everything, then hand the user the exact commands — you never run git.
Goal: get this release committed, tagged, merged, and published as a GitLab release.
- Confirm the version bump and changelog are in place (Build) and verified (Test).
- Draft a short MR description per \`.gitlab/merge_request_templates/Default.md\` and save it to \`.pi/mr/release-<version>.md\`. Title in Conventional Commits form, e.g. \`chore: release <version>\`.
- Create the MR yourself with \`glab mr create --title "chore: release <version>" --description "$(cat <path>)" --source-branch <branch>\` (project: dev/eigin on code.eigin.ai) — the release branch already exists, so this just opens the MR.
- You never commit, tag, or push. Give the user this exact checklist to run themselves:
    1. \`git add -A && git commit -m "chore: release <version>"\`
    2. \`git tag <version>\`
    3. \`git push && git push --tags\`
  (they'll have pushed before you can create the MR above — call this out up front, before step 3 of the checklist, so the ordering is clear)
- Then call wait_for_user (prompt "Review the MR and merge when ready"; confirmLabel "Continue to the GitLab release") — you never merge.
- Once merged, draft the GitLab release: pull the plan's "What's new" / "Breaking changes" sections into release notes. Check \`glab release list\` or the GitLab UI for prior releases to match tone/format.
- Give the user the command to create it, e.g. \`glab release create <version> --tag <version> --notes "$(cat <notes-path>)"\`, or point them to the GitLab UI if that's easier — you don't run it.
- Note explicitly: App Store submission is a separate, manual, human step — out of scope here.`,
    ),
  ],
};

export const WORKFLOWS: WorkflowDef[] = [FEATURE, BUG, PROTOTYPE, RELEASE];

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
