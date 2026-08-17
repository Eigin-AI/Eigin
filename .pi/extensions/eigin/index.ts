/**
 * Eigin extension — pi customizations for the Eigin workflow.
 *
 * Currently home to the workflow/stage state machine. A *workflow* is a
 * named, ordered subset of the shared stage vocabulary, tuned to a kind of
 * task (see workflow/workflows.ts):
 *   🧰 Feature   — context → plan → build → iterate → merge
 *   🐞 Bug       — context → plan → build → test → merge (plan skippable)
 *   🧬 Prototype — context → iterate → merge
 *
 * - Tracks the current workflow + stage and shows both in the footer.
 * - Prompts a workflow picker on brand-new sessions (no prior persisted
 *   state); resumed sessions restore silently.
 * - Gates edit/write tools per stage (read-only in context; plan is
 *   markdown-only).
 * - Injects stage-specific guidance as a per-turn hint on the latest user
 *   message (not the system prompt) to avoid invalidating the cached
 *   system-prompt/tool-defs prefix on every stage change (see workflow/stage-hint.ts).
 * - Suggests a model when the stage changes, resolved via the stage's model
 *   role (planner/builder/explorer) rather than a hardcoded model (you may
 *   decline). Configure roles with /eigin:role (see workflow/roles.ts).
 * - Lets the agent propose a transition via a confirm dialog (never automatic).
 * - Blocks stateful/destructive git, `terraform apply`/`destroy`, and
 *   `just infra deploy` (which wraps it) everywhere.
 * - Auto-names new sessions from a cheap one-shot LLM call on the first
 *   prompt, via pi.setSessionName() (see observability/generate-session-name.ts)
 *   — skipped for resumed/forked sessions and manual /name. This feeds pi's
 *   own terminal-title logic (`<app> - <name> - <cwd>`) and renames the
 *   session in /resume lists. Re-name anytime with /eigin:rename. Rings the
 *   terminal bell on agent_end so a pipelined, multi-terminal workflow
 *   surfaces which session just finished (Zed's integrated terminal ignores
 *   OSC 9/777 notify sequences but does show a bell as an attention
 *   indicator on unfocused tabs).
 * - Plan review is collaborative: the Plan stage co-edits a markdown file under
 *   .pi/plans/ (tracked as the "active plan", see workflow/active-plan.ts). The
 *   live file + a diff of the user's edits is injected each turn so direct
 *   edits are picked up without being flagged. Code review happens on the
 *   GitLab MR in the Merge stage. The wait_for_user tool (tools/wait-for-user.ts)
 *   hands control back for a signal instead of ending turns with prose.
 * - Persists workflow + stage across session resume (old sessions without a
 *   persisted workflow default to Feature).
 * - Maintains an agent-managed task list (add_tasks / resolve_tasks / clear_tasks),
 *   rendered alongside the stage instructions in the same per-turn block
 *   (see workflow/task-list.ts) so long-running, multi-step jobs don't lose
 *   track of what's left. A done/total count also shows in the footer.
 * - Provides an `explore` sub-agent (isolated `pi` subprocess) the main agent
 *   can delegate codebase/docs/web reconnaissance to (see tools/subagent/).
 *   The sub-agent's own eigin process runs in a stripped-down mode (detected
 *   via the EIGIN_SUBAGENT env var): only the web_search default is
 *   registered — no stage, no UI calls, no stage context leaked into the
 *   child. Guardrails (see below) still apply, since that package is loaded
 *   independently. See registerSubagentModeGuards below.
 * - Offers to compact context on Plan→Build — the one deliberate "big
 *   transition" — then auto-sends a kickoff with the approved plan inlined,
 *   so Build starts from a compacted context + the plan rather than the full
 *   planning discussion (see offerBuildHandoff below and workflow/build-handoff.ts).
 *
 * Commands / shortcuts (namespaced under `eigin:` to avoid colliding with
 * other extensions' commands):
 *   /eigin:workflow          show current workflow and switch to another
 *   /eigin:workflow <name>   switch workflow (feature|bug|prototype), landing on its first stage
 *   Ctrl+Alt+W               pick a workflow from a menu
 *   /eigin:stage             show current stage and the active workflow's stage sequence
 *   /eigin:stage <name>      switch to a stage within the current workflow
 *   /eigin:stage next|back   step along the current workflow's sequence
 *   Ctrl+Alt+S               pick a stage from a menu
 *   /eigin:role              pick a role, then a model, interactively
 *   /eigin:role <role>       pick a model for that role (planner|builder|explorer)
 *   /eigin:role <role> <id>  set a role's model directly ("provider/id" if ambiguous)
 *   /eigin:rename            regenerate the session name from the most recent user message
 *
 * Module layout:
 *   index.ts            wiring: footer, tool gating, guidance injection, persistence
 *   workflow/stages.ts    shared stage vocabulary + metadata (label/allowsEdits/role)
 *   workflow/workflows.ts  named stage sequences with per-workflow guidance (feature/bug/prototype)
 *   workflow/stage-hint.ts per-turn stage guidance, injected via the context event
 *   workflow/roles.ts     model roles (planner/builder/explorer) + built-in defaults
 *   workflow/role-store.ts persists per-developer role→model overrides (.pi/model-roles.json)
 *   tool-defaults.ts     project-scoped defaults for third-party tools (e.g. web_search)
 *   tools/               always-on interactive tools
 *     propose.ts           propose_stage (yes/no transition dialog)
 *     tasks.ts              add_tasks / resolve_tasks / clear_tasks (agent-managed checklist)
 *     confirm-dialog.ts    shared inline confirm-with-note dialog (used by propose + wait_for_user)
 *     wait-for-user.ts     wait_for_user (hand control back, block until the user signals)
 *     role-command.ts      /eigin:role command: configure role→model assignments
 *     ask/                 ask_questions (structured multi-question dialog)
 *       ask.ts               tool registration, schema, validation, result formatting
 *       ask-dialog.ts        the tabbed ctx.ui.custom state machine
 *       validation.ts        pure question/option count validation
 *     subagent/            explore sub-agent (vendored from pi's official example)
 *       index.ts             the subagent tool: spawns an isolated `pi` subprocess
 *       agents.ts            agent discovery (.pi/agents/*.md), unchanged from upstream
 *       model-role.ts        resolves an agent's `role:<name>` model to a real model id
 *   workflow/active-plan.ts  tracks the live plan file + diffs the user's edits for per-turn injection
 *   workflow/build-handoff.ts composes the Plan→Build compaction instructions + kickoff message
 *   workflow/task-list.ts pure task-list state (add/resolve/format), rendered with the stage hint
 *   observability/session-name.ts    pure prompt builder + name cleanup + last-user-text extraction
 *   observability/generate-session-name.ts one-shot LLM call producing the session name
 *   observability/bell.ts            terminal BEL write
 *   observability/herdr.ts           emits `herdr:blocked` around human-in-the-loop dialogs
 *
 * Herdr orchestration: when a pane parks on one of our dialogs (propose_stage,
 * wait_for_user, ask_questions, the model-switch/Plan→Build confirms, the
 * fresh-session workflow picker) we emit a `herdr:blocked` event on pi.events
 * (see observability/herdr.ts). Pi's official Herdr integration
 * (`herdr integration install pi`) consumes it and shows the pane as blocked —
 * "needs a decision" — rather than idle. It's a no-op without that integration.
 * Guardrails approval prompts emit the same event from @aliou/pi-guardrails.
 *
 * Hard-invariant enforcement (destructive git, terraform apply/destroy, `just
 * infra deploy`, secret files, outside-repo path access, dangerous shell
 * commands) lives in the @aliou/pi-guardrails package — see
 * .pi/extensions/guardrails.json. This extension no longer duplicates that
 * logic; it stays focused on workflow/stage machinery.
 */

import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import type { Theme } from "@earendil-works/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { ringBell } from "./observability/bell.ts";
import { withHerdrBlocked } from "./observability/herdr.ts";
import { generateSessionName } from "./observability/generate-session-name.ts";
import { extractLastUserText } from "./observability/session-name.ts";
import { WAIT_FOR_USER_TOOL, registerWaitForUserTool } from "./tools/wait-for-user.ts";
import {
  diffSinceSeen,
  markSeen,
  noActivePlan,
  setActivePlan,
  type ActivePlanState,
} from "./workflow/active-plan.ts";
import { buildCompactionInstructions, buildKickoff } from "./workflow/build-handoff.ts";
import { PROPOSE_TOOL, registerProposeTool } from "./tools/propose.ts";
import { ASK_QUESTIONS_TOOL, registerAskQuestionsTool } from "./tools/ask/ask.ts";
import { applySubagentDefaults, applyWebSearchDefault, type ToolCallInput } from "./tool-defaults.ts";
import {
  appendStageHintIfFreshTurn,
  buildStageHint,
  type StageHintMessage,
  type WorkflowStageView,
} from "./workflow/stage-hint.ts";
import { loadRoleOverrides, resolveRoleModel } from "./workflow/role-store.ts";
import { registerRoleCommand } from "./tools/role-command.ts";
import { registerSubagentTool } from "./tools/subagent/index.ts";
import { ADD_TASKS_TOOL, CLEAR_TASKS_TOOL, RESOLVE_TASKS_TOOL, registerTaskTools } from "./tools/tasks.ts";
import {
  addTasks,
  clearTasks,
  emptyTaskList,
  formatTaskList,
  resolveTasks,
  summarizeTaskList,
  type TaskListState,
} from "./workflow/task-list.ts";
import { isStageId, type StageDef, type StageId } from "./workflow/stages.ts";
import {
  firstStage,
  getStageInWorkflow,
  getWorkflow,
  isWorkflowId,
  relativeStageIn,
  WORKFLOWS,
  type WorkflowDef,
  type WorkflowId,
} from "./workflow/workflows.ts";

const EDIT_TOOLS = ["edit", "write"];
const ALWAYS_ON_TOOLS = [
  PROPOSE_TOOL,
  WAIT_FOR_USER_TOOL,
  ASK_QUESTIONS_TOOL,
  ADD_TASKS_TOOL,
  RESOLVE_TASKS_TOOL,
  CLEAR_TASKS_TOOL,
  "subagent",
];
const STATUS_KEY = "stage";
const TASKS_STATUS_KEY = "tasks";
const STATE_TYPE = "stage-mode";
const TASK_STATE_TYPE = "task-list";
const ACTIVE_PLAN_STATE_TYPE = "active-plan";
const DEFAULT_WORKFLOW: WorkflowId = "feature";

/** Icon + label for a workflow. */
function workflowLabel(w: WorkflowDef): string {
  return `${w.icon} ${w.label}`;
}

/** Two-line picker entry: `icon  Label` with a short muted summary underneath. */
function workflowOption(w: WorkflowDef, current: boolean, theme: Theme): string {
  const marker = current ? " (current)" : "";
  return `${workflowLabel(w)}${marker}\n  ${theme.fg("muted", w.summary)}`;
}

/** Set by tools/subagent/index.ts when spawning a sub-agent's child process. */
const SUBAGENT_ENV_VAR = "EIGIN_SUBAGENT";

/**
 * The eigin extension inside a sub-agent's child process. The child has no
 * concept of the parent's workflow stage and doesn't need one — it only sees
 * its own task. Register just the non-UI default: the web_search default.
 * Skip everything else (footer, tool gating, stage/role commands, model
 * suggestion, stage-hint injection, persistence) — all of it either needs a
 * UI the child doesn't have, or would clobber the `--tools` allowlist the
 * parent configured for this agent.
 *
 * Hard invariants (destructive git, terraform apply/destroy, `just infra
 * deploy`, secret files, outside-repo paths, dangerous commands) don't need
 * re-registering here: the @aliou/pi-guardrails package is loaded from
 * .pi/settings.json like any other extension, so it's active in the child
 * process too. Its non-interactive path (no UI to prompt in `-p` mode)
 * hard-blocks rather than hanging — see .pi/extensions/guardrails.json.
 */
function registerSubagentModeGuards(pi: ExtensionAPI): void {
  pi.on("tool_call", async (event) => {
    applyWebSearchDefault(event.toolName, event.input as ToolCallInput);
  });
}

export default function stageExtension(pi: ExtensionAPI): void {
  if (process.env[SUBAGENT_ENV_VAR]) {
    registerSubagentModeGuards(pi);
    return;
  }

  let currentWorkflow: WorkflowId = DEFAULT_WORKFLOW;
  let currentStage: StageId = firstStage(getWorkflow(DEFAULT_WORKFLOW));
  let taskListState: TaskListState = emptyTaskList();
  let activePlanState: ActivePlanState = noActivePlan();
  let sessionCwd = process.cwd();
  let hasAutoNamed = false;

  // --- Workflow/stage lookups ---------------------------------------------

  function activeWorkflow(): WorkflowDef {
    return getWorkflow(currentWorkflow);
  }

  /** The active workflow's tuned StageDef for `id` (defaults to the current stage). */
  function activeStage(id: StageId = currentStage): StageDef {
    return getStageInWorkflow(activeWorkflow(), id);
  }

  // --- Tool gating -------------------------------------------------------

  function applyStageTools(): void {
    const stage = activeStage();
    const active = pi.getActiveTools();
    const withoutEdit = active.filter((t) => !EDIT_TOOLS.includes(t));
    const next = stage.allowsEdits
      ? [...withoutEdit, ...EDIT_TOOLS]
      : withoutEdit;
    // The proposal, wait, and other always-on tools stay available every stage.
    pi.setActiveTools([...new Set([...next, ...ALWAYS_ON_TOOLS])]);
  }

  // --- Footer status -----------------------------------------------------

  function updateStatus(ctx: ExtensionContext): void {
    const workflow = activeWorkflow();
    const stage = activeStage();
    const color = stage.allowsEdits ? "success" : "warning";
    ctx.ui.setStatus(
      STATUS_KEY,
      ctx.ui.theme.fg(color, `${workflowLabel(workflow)} > ${stage.label}`),
    );
  }

  function persist(): void {
    pi.appendEntry(STATE_TYPE, { workflow: currentWorkflow, stage: currentStage });
  }

  // --- Session naming / bell ----------------------------------------------

  /**
   * Kicks off one-shot session naming, fire-and-forget so it never blocks
   * the turn it's triggered from. Names via pi.setSessionName() rather than
   * ctx.ui.setTitle() directly: this also renames the session in /resume
   * lists, and pi.setSessionName() is what feeds pi's own terminal-title
   * logic (see updateTerminalTitle below for how we then trim that title).
   */
  function maybeAutoNameSession(ctx: ExtensionContext, sourceText: string): void {
    if (hasAutoNamed || pi.getSessionName()) return;
    hasAutoNamed = true; // Mark handled regardless of outcome — never retry mid-session.
    void generateSessionName(ctx, sourceText)
      .then((name) => {
        if (name) pi.setSessionName(name);
      })
      .catch(() => {
        // Best-effort — e.g. ctx went stale from a session replacement mid-flight.
      });
  }

  /**
   * Trims pi's own terminal title down to `<app> - <name>`, dropping the
   * trailing ` - <cwd>` pi's interactive-mode appends by default (see
   * updateTerminalTitle() in interactive-mode.js). That suffix is redundant
   * for this workflow — the terminal is already scoped to one repo — and on
   * terminals that render the OSC title as the actual tab text (unlike Zed's
   * plain terminal panes, which only reflect it in the optional breadcrumb
   * toolbar) it reads as visual clutter: "<name> - eigin" when you're
   * already looking at the eigin terminal.
   *
   * pi's own title update runs synchronously off the same session_start /
   * session_info_changed events we hook here, so a same-tick ctx.ui.setTitle()
   * call could still lose the "last write wins" race depending on handler
   * registration order. Deferring via setTimeout(0) guarantees ours runs in
   * a later tick, after any core-side title write for the same event.
   */
  function updateTerminalTitle(ctx: ExtensionContext): void {
    if (!ctx.hasUI) return;
    const name = pi.getSessionName();
    if (!name) return; // No name yet — leave pi's own "<app> - <cwd>" default in place.
    setTimeout(() => ctx.ui.setTitle(`π - ${name}`), 0);
  }

  // --- Task list -----------------------------------------------------------

  function updateTaskStatus(ctx: ExtensionContext): void {
    const summary = summarizeTaskList(taskListState);
    if (summary) {
      ctx.ui.setStatus(TASKS_STATUS_KEY, ctx.ui.theme.fg("muted", summary));
    } else {
      ctx.ui.setStatus(TASKS_STATUS_KEY, undefined);
    }
  }

  function persistTasks(): void {
    pi.appendEntry(TASK_STATE_TYPE, taskListState);
  }

  // --- Active plan (collaborative plan file) -------------------------------

  /** True for a markdown file under `.pi/plans/` (the ephemeral plan area). */
  function isPlanFile(path: string): boolean {
    if (!path.endsWith(".md")) return false;
    const abs = resolve(sessionCwd, path);
    return abs.startsWith(`${resolve(sessionCwd, ".pi/plans")}/`);
  }

  // Only the path is persisted; last-seen content is in-memory (a resumed
  // session re-injects the plan fresh with no diff, which is correct).
  function persistActivePlan(): void {
    pi.appendEntry(ACTIVE_PLAN_STATE_TYPE, { path: activePlanState.path });
  }

  /**
   * The per-turn plan injection: the live plan file read fresh from disk, plus
   * a diff of what changed since the agent last saw it. Returns null when no
   * plan is active or the file can't be read. Updates last-seen as a side
   * effect so the next turn diffs against what was just shown.
   */
  async function buildPlanInjection(): Promise<string | null> {
    const path = activePlanState.path;
    if (!path) return null;
    let content: string;
    try {
      content = await readFile(resolve(sessionCwd, path), "utf-8");
    } catch {
      return null; // File gone or unreadable — skip this turn.
    }
    const diff = diffSinceSeen(activePlanState, content);
    activePlanState = markSeen(activePlanState, content);
    const diffBlock = diff
      ? `\n\nChanges since you last read it (the user's edits):\n\`\`\`diff\n${diff}\n\`\`\``
      : "";
    return `The live plan file (${path}) — re-read fresh each turn; respond to the user's edits/notes:\n\`\`\`markdown\n${content}\n\`\`\`${diffBlock}`;
  }

  // --- Model suggestion --------------------------------------------------

  async function suggestModel(
    stage: StageDef,
    ctx: ExtensionContext,
  ): Promise<void> {
    if (!ctx.hasUI) return; // Dialogs aren't available in -p/JSON mode.
    if (!stage.role) return;
    const pref = resolveRoleModel(stage.role, loadRoleOverrides());
    if (ctx.model?.provider === pref.provider && ctx.model?.id === pref.id)
      return;

    const model = ctx.modelRegistry.find(pref.provider, pref.id);
    if (!model) return; // Preferred model not configured; skip silently.

    const ok = await withHerdrBlocked(pi, `Switch model for ${stage.label}?`, () =>
      ctx.ui.confirm(
        `Switch model for ${stage.label}?`,
        `Use ${pref.id} for the ${stage.label} stage? (current: ${ctx.model?.id ?? "none"})`,
      ),
    );
    if (!ok) return;

    const success = await pi.setModel(model);
    ctx.ui.notify(
      success ? `Model → ${pref.id}` : `No API key for ${pref.id}`,
      success ? "info" : "error",
    );
  }

  // --- Transitions -------------------------------------------------------

  /**
   * Offers to compact the conversation before entering Build — the one
   * deliberate "big transition" where context-gathering ends and focused
   * implementation begins (see workflow/build-handoff.ts). Runs compaction on
   * the *current* (planner) model, then switches to the builder model, then
   * auto-sends a kickoff message with the approved plan inlined — in that
   * order, via ctx.compact()'s onComplete, since compact() is deferred/fire-
   * and-forget rather than awaitable.
   *
   * Returns whether a kickoff was scheduled, so callers (propose_stage) know
   * whether to end the turn quietly (kickoff will start a fresh one) or give
   * the normal stage-guidance continuation (declined — nothing else is coming).
   */
  async function offerBuildHandoff(ctx: ExtensionContext): Promise<boolean> {
    const buildStage = activeStage("build");
    const ok = await withHerdrBlocked(pi, "Compact context before Build?", () =>
      ctx.ui.confirm(
        "Compact context before Build?",
        "The approved plan is already saved as a file. Summarize the planning discussion (decisions, constraints, discoveries) and start Build from a compacted context + the plan, instead of carrying the full discussion forward.",
      ),
    );
    if (!ok) {
      await suggestModel(buildStage, ctx);
      return false;
    }

    const planPath = activePlanState.path;
    let planContent: string | null = null;
    if (planPath) {
      try {
        planContent = await readFile(planPath, "utf-8");
      } catch {
        planContent = null; // Best-effort — kickoff falls back to the no-plan text.
      }
    }

    const startBuild = () => {
      void suggestModel(buildStage, ctx).then(() => {
        pi.sendUserMessage(buildKickoff(planPath, planContent));
      });
    };

    ctx.compact({
      customInstructions: buildCompactionInstructions(planPath),
      onComplete: startBuild,
      onError: (err) => {
        ctx.ui.notify(`Compaction failed: ${err.message}`, "warning");
        startBuild(); // Don't strand the transition — proceed to Build anyway.
      },
    });
    return true;
  }

  async function setStage(
    id: StageId,
    ctx: ExtensionContext,
    opts?: { suggestModel?: boolean },
  ): Promise<{ handoffPending: boolean }> {
    const from = currentStage;
    const stage = activeStage(id);
    const changed = currentStage !== id;
    currentStage = id;
    applyStageTools();
    updateStatus(ctx);
    persist();
    ctx.ui.notify(
      `Stage → ${stage.label}${stage.allowsEdits ? "" : " (read-only)"}`,
      "info",
    );
    if (!changed || opts?.suggestModel === false) return { handoffPending: false };

    if (from === "plan" && id === "build" && ctx.hasUI) {
      return { handoffPending: await offerBuildHandoff(ctx) };
    }

    await suggestModel(stage, ctx);
    return { handoffPending: false };
  }

  /** Switch workflows, landing on the new workflow's first stage. */
  async function setWorkflow(id: WorkflowId, ctx: ExtensionContext): Promise<void> {
    const changed = currentWorkflow !== id;
    currentWorkflow = id;
    const workflow = activeWorkflow();
    const entry = firstStage(workflow);
    currentStage = entry;
    applyStageTools();
    updateStatus(ctx);
    persist();
    if (!changed) return;
    ctx.ui.notify(`Workflow → ${workflowLabel(workflow)}`, "info");
    await suggestModel(activeStage(entry), ctx);
  }

  // --- Command / shortcut ------------------------------------------------

  pi.registerCommand("eigin:stage", {
    description:
      "Show or set the stage within the current workflow (see /eigin:workflow for the workflow itself)",
    getArgumentCompletions: (prefix: string) => {
      const options = [...activeWorkflow().stages.map((s) => s.id), "next", "back"];
      const items = options
        .filter((o) => o.startsWith(prefix))
        .map((o) => ({ value: o, label: o }));
      return items.length > 0 ? items : null;
    },
    handler: async (args, ctx) => {
      const arg = args.trim().toLowerCase();
      const workflow = activeWorkflow();

      if (arg === "") {
        const list = workflow.stages.map((s) => {
          const marker = s.id === currentStage ? "▶" : " ";
          const mode = s.allowsEdits ? "edit" : "read-only";
          return `${marker} ${s.label} (${mode})`;
        }).join("\n");
        ctx.ui.notify(`${workflow.icon} ${workflow.label}:\n${list}`, "info");
        return;
      }

      if (arg === "next" || arg === "back") {
        const target = relativeStageIn(workflow, currentStage, arg === "next" ? 1 : -1);
        await setStage(target.id, ctx);
        return;
      }

      if (isStageId(arg) && workflow.stages.some((s) => s.id === arg)) {
        await setStage(arg, ctx);
        return;
      }

      ctx.ui.notify(
        `Unknown stage: "${arg}" for the ${workflow.label} workflow. Try: ${workflow.stages.map((s) => s.id).join(", ")}`,
        "error",
      );
    },
  });

  pi.registerShortcut("ctrl+alt+s", {
    description: "Pick a workflow stage",
    handler: async (ctx) => {
      const workflow = activeWorkflow();
      const labels = workflow.stages.map(
        (s) => `${s.label}${s.id === currentStage ? " (current)" : ""}`,
      );
      const choice = await ctx.ui.select("Set stage:", labels);
      if (!choice) return;
      const picked = workflow.stages.find((s) => choice.includes(s.label));
      if (picked) await setStage(picked.id, ctx);
    },
  });

  // --- Workflow command / shortcut ----------------------------------------

  pi.registerCommand("eigin:workflow", {
    description: "Show or switch the workflow (feature|bug|prototype)",
    getArgumentCompletions: (prefix: string) => {
      const items = WORKFLOWS.map((w) => w.id)
        .filter((o) => o.startsWith(prefix))
        .map((o) => ({ value: o, label: o }));
      return items.length > 0 ? items : null;
    },
    handler: async (args, ctx) => {
      const arg = args.trim().toLowerCase();

      if (arg === "") {
        const list = WORKFLOWS.map((w) => {
          const marker = w.id === currentWorkflow ? "▶" : " ";
          return `${marker} ${workflowLabel(w)}\n    ${ctx.ui.theme.fg("muted", w.summary)}`;
        }).join("\n");
        ctx.ui.notify(`Workflows:\n${list}`, "info");
        return;
      }

      if (isWorkflowId(arg)) {
        await setWorkflow(arg, ctx);
        return;
      }

      ctx.ui.notify(
        `Unknown workflow: "${arg}". Try: ${WORKFLOWS.map((w) => w.id).join(", ")}`,
        "error",
      );
    },
  });

  pi.registerShortcut("ctrl+alt+w", {
    description: "Pick a workflow",
    handler: async (ctx) => {
      const labels = WORKFLOWS.map((w) => workflowOption(w, w.id === currentWorkflow, ctx.ui.theme));
      const choice = await ctx.ui.select("Set workflow:", labels);
      if (!choice) return;
      const picked = WORKFLOWS.find((w) => choice.includes(w.label));
      if (picked) await setWorkflow(picked.id, ctx);
    },
  });

  // --- Tools -------------------------------------------------------------

  registerProposeTool(pi, {
    current: () => currentStage,
    currentWorkflow: () => currentWorkflow,
    setStage,
  });
  registerAskQuestionsTool(pi);
  registerRoleCommand(pi, { activeRole: () => activeStage().role });
  registerSubagentTool(pi);
  registerTaskTools(pi, {
    add(texts, ctx) {
      const result = addTasks(taskListState, texts);
      taskListState = result.state;
      persistTasks();
      updateTaskStatus(ctx);
      return result;
    },
    resolve(ids, ctx) {
      const result = resolveTasks(taskListState, ids);
      taskListState = result.state;
      persistTasks();
      updateTaskStatus(ctx);
      return result;
    },
    clear(ctx) {
      taskListState = clearTasks(taskListState);
      persistTasks();
      updateTaskStatus(ctx);
      return { state: taskListState };
    },
  });

  registerWaitForUserTool(pi, {
    stage: () => currentStage,
    planInjection: () => buildPlanInjection(),
  });

  // --- Session naming / bell events ---------------------------------------

  // Auto-name on the first prompt of a session (skipped if already named —
  // manual /name, a resumed/forked session, or an earlier auto-name this run).
  pi.on("before_agent_start", async (event, ctx) => {
    if (!ctx.hasUI || !event.prompt?.trim()) return;
    maybeAutoNameSession(ctx, event.prompt);
  });

  // Fires for auto-naming, manual /name, and /eigin:rename alike (all three
  // go through pi.setSessionName()) — trim the resulting title every time.
  pi.on("session_info_changed", async (_event, ctx) => {
    updateTerminalTitle(ctx);
  });

  pi.registerCommand("eigin:rename", {
    description: "Regenerate the session name from the most recent user message",
    handler: async (_args, ctx) => {
      const lastPrompt = extractLastUserText(ctx.sessionManager.getEntries());
      if (!lastPrompt) {
        ctx.ui.notify("No user message to name the session from.", "warning");
        return;
      }
      const name = await generateSessionName(ctx, lastPrompt);
      if (name) {
        pi.setSessionName(name);
        ctx.ui.notify(`Session renamed: ${name}`, "info");
      } else {
        ctx.ui.notify("Could not generate a session name (no model or API key?).", "warning");
      }
    },
  });

  pi.on("agent_end", async (_event, ctx) => {
    if (ctx.mode === "tui") ringBell(); // Zed shows this as an attention dot on unfocused tabs.
  });

  // --- Stage write scope ---------------------------------------------

  pi.on("tool_call", async (event) => {
    // Project-scoped default: web_search skips the browser curator unless the
    // caller asked for a specific workflow (see tool-defaults.ts).
    applyWebSearchDefault(event.toolName, event.input as ToolCallInput);
    // Project-scoped default: subagent finds our committed .pi/agents/*.md
    // without a per-call confirmation prompt (see tool-defaults.ts).
    applySubagentDefaults(event.toolName, event.input as ToolCallInput);

    // Plan stage: restrict write/edit to markdown, and track the live plan file.
    if (
      currentStage === "plan" &&
      (event.toolName === "write" || event.toolName === "edit")
    ) {
      const path = (event.input as { path?: string }).path ?? "";
      if (!path.endsWith(".md")) {
        return {
          block: true,
          reason:
            "Plan stage: writes/edits restricted to markdown files (.md). Code changes are blocked until Build.",
        };
      }
      // Track the live plan file when one under .pi/plans/ is written.
      if (isPlanFile(path)) {
        const next = setActivePlan(activePlanState, path);
        if (next !== activePlanState) {
          activePlanState = next;
          persistActivePlan();
        }
      }
    }
  });

  // --- Stage-specific guidance -------------------------------------------

  // The static invariants never change, so they stay in the system prompt —
  // identical text every turn keeps the cached system-prompt/tool-defs prefix
  // intact. Stage-specific guidance varies by stage, so it's injected
  // per-turn on the latest user message instead (see the `context` handler
  // below) rather than here, to avoid invalidating that cached prefix on
  // every stage change.
  pi.on("before_agent_start", async (event) => {
    return {
      systemPrompt: `${event.systemPrompt}

Always blocked (every stage): the agent should not run stateful or destructive git (commit, push, pull, fetch, merge, rebase, reset, checkout/switch, branch changes), \`terraform apply\`/\`destroy\`, or \`just infra deploy\` (which wraps it). These are the user's to run — discuss them or say what to try.`,
    };
  });

  pi.on("context", async (event) => {
    const workflow = activeWorkflow();
    const stage = activeStage();
    const taskBlock = formatTaskList(taskListState);
    let guidance = taskBlock ? `${stage.guidance}\n\n${taskBlock}` : stage.guidance;

    // Collaborative plan: on a fresh user turn while co-editing, inject the
    // live plan file + a diff of the user's edits so they're picked up without
    // being flagged. Rides the same fresh-turn gate as the stage hint.
    const msgs = event.messages as StageHintMessage[];
    const lastMsg = msgs[msgs.length - 1];
    if (lastMsg?.role === "user" && activePlanState.path && stage.id === "plan") {
      const planBlock = await buildPlanInjection();
      if (planBlock) guidance = `${guidance}\n\n${planBlock}`;
    }

    const view: WorkflowStageView = {
      workflowLabel: workflow.label,
      workflowIcon: workflow.icon,
      stages: workflow.stages.map((s) => ({ id: s.id, label: s.label })),
      currentId: stage.id,
    };
    const hint = buildStageHint(view, guidance);
    const messages = appendStageHintIfFreshTurn(msgs, hint);
    return { messages: messages as unknown as typeof event.messages };
  });

  // --- Persistence / restore ---------------------------------------------

  pi.on("session_start", async (_event, ctx) => {
    sessionCwd = ctx.cwd;
    const entries = ctx.sessionManager.getEntries();
    const last = entries
      .filter(
        (e: { type: string; customType?: string }) =>
          e.type === "custom" && e.customType === STATE_TYPE,
      )
      .pop() as { data?: { workflow?: WorkflowId; stage?: StageId } } | undefined;

    const isFreshSession = last === undefined;

    // Old sessions persisted only `stage`, no `workflow` — default to Feature
    // (today's pipeline) rather than losing the restored stage.
    const restoredWorkflow = last?.data?.workflow;
    currentWorkflow = restoredWorkflow && isWorkflowId(restoredWorkflow) ? restoredWorkflow : DEFAULT_WORKFLOW;

    const restoredStage = last?.data?.stage;
    const workflow = activeWorkflow();
    currentStage =
      restoredStage && isStageId(restoredStage) && workflow.stages.some((s) => s.id === restoredStage)
        ? restoredStage
        : firstStage(workflow); // Restored stage isn't part of this workflow (or none persisted) — start fresh.

    const lastTasks = entries
      .filter(
        (e: { type: string; customType?: string }) =>
          e.type === "custom" && e.customType === TASK_STATE_TYPE,
      )
      .pop() as { data?: TaskListState } | undefined;
    if (lastTasks?.data) taskListState = lastTasks.data;

    // Restore the active plan file so a resumed session keeps co-editing it.
    const lastPlan = entries
      .filter(
        (e: { type: string; customType?: string }) =>
          e.type === "custom" && e.customType === ACTIVE_PLAN_STATE_TYPE,
      )
      .pop() as { data?: { path?: string } } | undefined;
    if (lastPlan?.data?.path) {
      activePlanState = setActivePlan(noActivePlan(), lastPlan.data.path);
    }

    // Brand-new session (nothing persisted yet): let the user pick a workflow
    // up front instead of silently defaulting to Feature.
    if (isFreshSession && ctx.hasUI) {
      const labels = WORKFLOWS.map((w) => workflowOption(w, false, ctx.ui.theme));
      const choice = await withHerdrBlocked(pi, "Pick a workflow", () =>
        ctx.ui.select("Pick a workflow:", labels),
      );
      const picked = choice ? WORKFLOWS.find((w) => choice.includes(w.label)) : undefined;
      if (picked) {
        currentWorkflow = picked.id;
        currentStage = firstStage(getWorkflow(picked.id));
      }
    }

    // Resumed/forked sessions (or a manual /name) already carry a name —
    // don't auto-rename over it. New sessions get exactly one auto-name shot,
    // fired from before_agent_start on the first prompt.
    hasAutoNamed = !!pi.getSessionName();

    applyStageTools();
    updateStatus(ctx);
    updateTaskStatus(ctx);
    updateTerminalTitle(ctx); // Resumed/forked sessions already have a name — trim the title pi sets on rebind.
    persist(); // Ensure a freshly-picked (or defaulted) workflow/stage is recorded even if nothing else changes it.
    await suggestModel(activeStage(), ctx);
  });
}
