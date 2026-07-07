/**
 * Eigin extension — pi customizations for the Eigin workflow.
 *
 * Currently home to the stage state machine (a workflow pipeline for pi):
 * Pipeline: context → plan → build → iterate → review → merge
 *
 * - Tracks the current stage and shows it in the footer.
 * - Gates edit/write tools per stage (read-only in context/merge; plan is
 *   markdown-only).
 * - Injects stage-specific guidance as a per-turn hint on the latest user
 *   message (not the system prompt) to avoid invalidating the cached
 *   system-prompt/tool-defs prefix on every stage change (see workflow/stage-hint.ts).
 * - Suggests a model when the stage changes, resolved via the stage's model
 *   role (planner/builder/explorer) rather than a hardcoded model (you may
 *   decline). Configure roles with /role (see workflow/roles.ts).
 * - Lets the agent propose a transition via a confirm dialog (never automatic).
 * - Blocks stateful/destructive git, `terraform apply`/`destroy`, and
 *   `just infra deploy` (which wraps it) everywhere.
 * - Integrates Plannotator as a review UI (see tools/plannotator.ts).
 * - Persists across session resume.
 * - Provides an `explore` sub-agent (isolated `pi` subprocess) the main agent
 *   can delegate codebase/docs/web reconnaissance to (see tools/subagent/).
 *   The sub-agent's own eigin process runs in a stripped-down mode (detected
 *   via the EIGIN_SUBAGENT env var): only the bash guardrail and web_search
 *   default are registered — no stage, no UI calls, no stage context leaked
 *   into the child. See registerSubagentModeGuards below.
 * - Offers to compact context on Plan→Build — the one deliberate "big
 *   transition" — then auto-sends a kickoff with the approved plan inlined,
 *   so Build starts from a compacted context + the plan rather than the full
 *   planning discussion (see offerBuildHandoff below and workflow/build-handoff.ts).
 *
 * Commands / shortcuts:
 *   /stage             show current stage and the pipeline
 *   /stage <name>      switch to a stage (context|plan|build|iterate|review|merge)
 *   /stage next|back   step along the pipeline
 *   Ctrl+Alt+S         pick a stage from a menu
 *   /role              pick a role, then a model, interactively
 *   /role <role>       pick a model for that role (planner|builder|explorer)
 *   /role <role> <id>  set a role's model directly ("provider/id" if ambiguous)
 *
 * Module layout:
 *   index.ts            wiring: footer, tool gating, guidance injection, persistence
 *   workflow/stages.ts   the pipeline state machine (stage defs, transitions)
 *   workflow/stage-hint.ts per-turn stage guidance, injected via the context event
 *   workflow/roles.ts     model roles (planner/builder/explorer) + built-in defaults
 *   workflow/role-store.ts persists per-developer role→model overrides (.pi/model-roles.json)
 *   guardrails/guards.ts pure invariant checks (destructive git, terraform apply)
 *   tool-defaults.ts     project-scoped defaults for third-party tools (e.g. web_search)
 *   tools/               always-on interactive tools
 *     propose.ts           propose_stage (yes/no transition dialog)
 *     confirm-dialog.ts    shared inline confirm-with-note dialog (used by propose)
 *     plannotator.ts       submit_plan / submit_review (Plannotator UI)
 *     role-command.ts      /role command: configure role→model assignments
 *     ask/                 ask_questions (structured multi-question dialog)
 *       ask.ts               tool registration, schema, validation, result formatting
 *       ask-dialog.ts        the tabbed ctx.ui.custom state machine
 *       validation.ts        pure question/option count validation
 *     subagent/            explore sub-agent (vendored from pi's official example)
 *       index.ts             the subagent tool: spawns an isolated `pi` subprocess
 *       agents.ts            agent discovery (.pi/agents/*.md), unchanged from upstream
 *       model-role.ts        resolves an agent's `role:<name>` model to a real model id
 *   workflow/build-handoff.ts composes the Plan→Build compaction instructions + kickoff message
 */

import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { checkCommand } from "./guardrails/guards.ts";
import {
  getLastApprovedPlanPath,
  registerPlannotator,
  SUBMIT_PLAN_TOOL,
  SUBMIT_REVIEW_TOOL,
} from "./tools/plannotator.ts";
import { buildCompactionInstructions, buildKickoff } from "./workflow/build-handoff.ts";
import { PROPOSE_TOOL, registerProposeTool } from "./tools/propose.ts";
import { ASK_QUESTIONS_TOOL, registerAskQuestionsTool } from "./tools/ask/ask.ts";
import { applySubagentDefaults, applyWebSearchDefault, type ToolCallInput } from "./tool-defaults.ts";
import { appendStageHintIfFreshTurn, buildStageHint, type StageHintMessage } from "./workflow/stage-hint.ts";
import { loadRoleOverrides, resolveRoleModel } from "./workflow/role-store.ts";
import { registerRoleCommand } from "./tools/role-command.ts";
import { registerSubagentTool } from "./tools/subagent/index.ts";
import {
  getStage,
  isStageId,
  relativeStage,
  type StageDef,
  type StageId,
  STAGES,
} from "./workflow/stages.ts";

const EDIT_TOOLS = ["edit", "write"];
const ALWAYS_ON_TOOLS = [PROPOSE_TOOL, SUBMIT_PLAN_TOOL, SUBMIT_REVIEW_TOOL, ASK_QUESTIONS_TOOL, "subagent"];
const STATUS_KEY = "stage";
const STATE_TYPE = "stage-mode";
const DEFAULT_STAGE: StageId = "context";

/** Set by tools/subagent/index.ts when spawning a sub-agent's child process. */
const SUBAGENT_ENV_VAR = "EIGIN_SUBAGENT";

/**
 * The eigin extension inside a sub-agent's child process. The child has no
 * concept of the parent's workflow stage and doesn't need one — it only sees
 * its own task. Register just the non-UI, always-correct invariants: the bash
 * guardrail (git-write/terraform/`just infra deploy` stay blocked even in the
 * child) and the web_search default. Skip everything else (footer, tool
 * gating, stage/role commands, model suggestion, stage-hint injection,
 * persistence) — all of it either needs a UI the child doesn't have, or would
 * clobber the `--tools` allowlist the parent configured for this agent.
 */
function registerSubagentModeGuards(pi: ExtensionAPI): void {
  pi.on("tool_call", async (event) => {
    applyWebSearchDefault(event.toolName, event.input as ToolCallInput);

    if (event.toolName === "bash") {
      const command = (event.input as { command?: string }).command ?? "";
      const violation = checkCommand(command);
      if (violation) return { block: true, reason: violation.reason };
    }
  });
}

export default function stageExtension(pi: ExtensionAPI): void {
  if (process.env[SUBAGENT_ENV_VAR]) {
    registerSubagentModeGuards(pi);
    return;
  }

  let currentStage: StageId = DEFAULT_STAGE;

  // --- Tool gating -------------------------------------------------------

  function applyStageTools(): void {
    const stage = getStage(currentStage);
    const active = pi.getActiveTools();
    const withoutEdit = active.filter((t) => !EDIT_TOOLS.includes(t));
    const next = stage.allowsEdits
      ? [...withoutEdit, ...EDIT_TOOLS]
      : withoutEdit;
    // The proposal and Plannotator tools stay available in every stage.
    pi.setActiveTools([...new Set([...next, ...ALWAYS_ON_TOOLS])]);
  }

  // --- Footer status -----------------------------------------------------

  function updateStatus(ctx: ExtensionContext): void {
    const stage = getStage(currentStage);
    const color = stage.allowsEdits ? "success" : "warning";
    ctx.ui.setStatus(
      STATUS_KEY,
      ctx.ui.theme.fg(color, `${stage.icon} ${stage.label}`),
    );
  }

  function persist(): void {
    pi.appendEntry(STATE_TYPE, { stage: currentStage });
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

    const ok = await ctx.ui.confirm(
      `Switch model for ${stage.label}?`,
      `Use ${pref.id} for the ${stage.label} stage? (current: ${ctx.model?.id ?? "none"})`,
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
    const buildStage = getStage("build");
    const ok = await ctx.ui.confirm(
      "Compact context before Build?",
      "The approved plan is already saved as a file. Summarize the planning discussion (decisions, constraints, discoveries) and start Build from a compacted context + the plan, instead of carrying the full discussion forward.",
    );
    if (!ok) {
      await suggestModel(buildStage, ctx);
      return false;
    }

    const planPath = getLastApprovedPlanPath();
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
    const stage = getStage(id);
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

  // --- Command / shortcut ------------------------------------------------

  pi.registerCommand("stage", {
    description:
      "Show or set the workflow stage (context|plan|build|iterate|review|merge)",
    getArgumentCompletions: (prefix: string) => {
      const options = [...STAGES.map((s) => s.id), "next", "back"];
      const items = options
        .filter((o) => o.startsWith(prefix))
        .map((o) => ({ value: o, label: o }));
      return items.length > 0 ? items : null;
    },
    handler: async (args, ctx) => {
      const arg = args.trim().toLowerCase();

      if (arg === "") {
        const list = STAGES.map((s) => {
          const marker = s.id === currentStage ? "▶" : " ";
          const mode = s.allowsEdits ? "edit" : "read-only";
          return `${marker} ${s.icon} ${s.label} (${mode})`;
        }).join("\n");
        ctx.ui.notify(`Pipeline:\n${list}`, "info");
        return;
      }

      if (arg === "next" || arg === "back") {
        const target = relativeStage(currentStage, arg === "next" ? 1 : -1);
        await setStage(target.id, ctx);
        return;
      }

      if (isStageId(arg)) {
        await setStage(arg, ctx);
        return;
      }

      ctx.ui.notify(
        `Unknown stage: "${arg}". Try: ${STAGES.map((s) => s.id).join(", ")}`,
        "error",
      );
    },
  });

  pi.registerShortcut("ctrl+alt+s", {
    description: "Pick a workflow stage",
    handler: async (ctx) => {
      const labels = STAGES.map(
        (s) =>
          `${s.icon} ${s.label}${s.id === currentStage ? " (current)" : ""}`,
      );
      const choice = await ctx.ui.select("Set stage:", labels);
      if (!choice) return;
      const picked = STAGES.find((s) => choice.includes(s.label));
      if (picked) await setStage(picked.id, ctx);
    },
  });

  // --- Tools -------------------------------------------------------------

  registerProposeTool(pi, { current: () => currentStage, setStage });
  registerAskQuestionsTool(pi);
  registerRoleCommand(pi, { activeRole: () => getStage(currentStage).role });
  registerSubagentTool(pi);

  const cleanupPlannotator = registerPlannotator(pi);
  pi.on("session_shutdown", async () => {
    cleanupPlannotator();
  });

  // --- Always-blocked commands + stage write scope -----------------------

  pi.on("tool_call", async (event) => {
    // Project-scoped default: web_search skips the browser curator unless the
    // caller asked for a specific workflow (see tool-defaults.ts).
    applyWebSearchDefault(event.toolName, event.input as ToolCallInput);
    // Project-scoped default: subagent finds our committed .pi/agents/*.md
    // without a per-call confirmation prompt (see tool-defaults.ts).
    applySubagentDefaults(event.toolName, event.input as ToolCallInput);

    // Block destructive bash commands (every stage).
    if (event.toolName === "bash") {
      const command = (event.input as { command?: string }).command ?? "";
      const violation = checkCommand(command);
      if (violation) return { block: true, reason: violation.reason };
    }

    // In the Plan stage, restrict write/edit to markdown files only.
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
    const stage = getStage(currentStage);
    const hint = buildStageHint(stage.label, stage.guidance);
    const messages = appendStageHintIfFreshTurn(event.messages as StageHintMessage[], hint);
    return { messages: messages as unknown as typeof event.messages };
  });

  // --- Persistence / restore ---------------------------------------------

  pi.on("session_start", async (_event, ctx) => {
    const entries = ctx.sessionManager.getEntries();
    const last = entries
      .filter(
        (e: { type: string; customType?: string }) =>
          e.type === "custom" && e.customType === STATE_TYPE,
      )
      .pop() as { data?: { stage?: StageId } } | undefined;

    const restored = last?.data?.stage;
    if (restored && isStageId(restored)) currentStage = restored;

    applyStageTools();
    updateStatus(ctx);
    await suggestModel(getStage(currentStage), ctx);
  });
}
