/**
 * Agent-initiated stage transitions.
 *
 * The `propose_stage` tool lets the agent suggest advancing the workflow. It
 * shows a confirm-with-note dialog inline (mid-turn), returns the user's
 * decision, and lets the agent react in the same turn. The user always decides;
 * a transition never happens automatically.
 */

import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { confirmWithNote } from "./confirm-dialog.ts";
import { withHerdrBlocked } from "../observability/herdr.ts";
import { STAGE_META, type StageId } from "../workflow/stages.ts";
import { loadGuidance } from "../workflow/guidance.ts";
import { getStageInWorkflow, getWorkflow, hasStage, relativeStageIn, type WorkflowId } from "../workflow/workflows.ts";

export const PROPOSE_TOOL = "propose_stage";

/** Read/write access to the current workflow + stage, owned by the extension. */
export interface StageController {
  current(): StageId;
  currentWorkflow(): WorkflowId;
  /** AFK mode auto-approves the transition without showing the dialog. */
  isAfk(): boolean;
  setStage(
    id: StageId,
    ctx: ExtensionContext,
    opts?: { suggestModel?: boolean },
  ): Promise<{ handoffPending: boolean }>;
}

export function registerProposeTool(
  pi: ExtensionAPI,
  controller: StageController,
): void {
  // The full stage vocabulary, for typebox's static enum — validated against
  // the *active workflow* at execute time (a workflow may not include every
  // stage, e.g. Bug has no review).
  const schema = Type.Object({
    stage: Type.Optional(StringEnum(Object.keys(STAGE_META) as [string, ...string[]])),
    reason: Type.Optional(Type.String()),
  });

  pi.registerTool({
    name: PROPOSE_TOOL,
    label: "Propose Stage",
    description:
      "Propose advancing the workflow. Omit `stage` to move to the NEXT stage — the normal, preferred path. " +
      "Pass a specific stage only to skip ahead or step back, which should be rare (advance one stage at a " +
      "time). Shows the user a yes/no dialog (they may attach a note) and returns their decision. The " +
      "per-turn hint names the next stage and the valid targets. Act on the returned result: if approved " +
      "you are now in the new stage; if declined, honor any note. Never assume the transition happened.",
    promptSnippet:
      "Propose advancing the workflow to another stage (user confirms in a dialog)",
    promptGuidelines: [
      `Call ${PROPOSE_TOOL} to advance when a stage is complete — omit \`stage\` to go to the next stage (advance one at a time; only name a stage to skip or go back, which is rare). It prompts the user itself, so do not add your own "here's the dialog" narration.`,
    ],
    parameters: schema,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const workflow = getWorkflow(controller.currentWorkflow());
      // Default (no stage) = the next stage in this workflow's sequence.
      const target = (params.stage as StageId | undefined) ??
        relativeStageIn(workflow, controller.current(), 1).id;
      const here = () => getStageInWorkflow(workflow, controller.current()).label;

      // Target stage isn't part of the active workflow — report the valid
      // stages instead of prompting for an impossible transition (e.g.
      // proposing "review" while in the Bug workflow, which has none). No
      // `terminate` here (unlike the cancelled/declined-without-note cases
      // below): this is the agent's own mistake, not a user decision, so it
      // should get an automatic follow-up call and self-correct by proposing
      // a valid stage in the same turn rather than surfacing a raw rejection
      // that the user has to notice and relay back.
      if (!hasStage(workflow, target)) {
        const valid = workflow.stages.map((s) => s.id).join(", ");
        return {
          content: [
            {
              type: "text",
              text: `The ${workflow.label} workflow has no "${target}" stage. Valid stages here: ${valid}.`,
            },
          ],
          details: { stage: target, decision: "not-in-workflow" },
        };
      }

      const stage = getStageInWorkflow(workflow, target);

      // Already in the target stage — don't prompt for a no-op transition.
      // (The in-context stage view can go stale after a manual /eigin:stage switch.)
      if (target === controller.current()) {
        return {
          content: [
            {
              type: "text",
              text: `Already in the ${stage.label} stage. No transition needed.`,
            },
          ],
          details: { stage: target, decision: "already-here" },
        };
      }

      // Non-interactive: can't prompt. Report the proposal and stop.
      if (ctx.mode !== "tui" || !ctx.hasUI) {
        return {
          content: [
            {
              type: "text",
              text: `Proposed moving to ${stage.label}, but no UI is available to confirm.`,
            },
          ],
          details: { stage: target, decision: "unavailable" },
          terminate: true,
        };
      }

      const detail = params.reason
        ? params.reason
        : `Move to the ${stage.label} stage?`;

      // AFK: skip the prompt entirely and proceed as if the user approved.
      // No `herdr:blocked` is emitted — the point of AFK is to not stall.
      const result = controller.isAfk()
        ? { confirmed: true }
        : await withHerdrBlocked(pi, `Advance to ${stage.label}?`, () =>
            confirmWithNote(ctx.ui, `Advance to ${stage.label}?`, detail),
          );

      // Esc / cancel — stay put, nothing to react to.
      if (!result) {
        return {
          content: [
            {
              type: "text",
              text: `User cancelled. Staying in the ${here()} stage.`,
            },
          ],
          details: { stage: target, decision: "cancelled" },
          terminate: true,
        };
      }

      const { confirmed, note } = result;

      if (!confirmed) {
        // A note ("no, do X first") is addressed in this same turn.
        if (note) {
          return {
            content: [
              {
                type: "text",
                text: `User declined moving to ${stage.label}. They added: "${note}". Stay in the ${here()} stage and address this.`,
              },
            ],
            details: { stage: target, decision: "declined", note },
          };
        }
        return {
          content: [
            {
              type: "text",
              text: `User declined. Staying in the ${here()} stage.`,
            },
          ],
          details: { stage: target, decision: "declined" },
          terminate: true,
        };
      }

      // Approved — switch stage now, then continue this turn in the new stage.
      const { handoffPending } = await controller.setStage(target, ctx);

      // A handoff is running (compaction into Build, or the review into
      // Merge) and has already scheduled a kickoff message to start a fresh
      // turn. End this turn quietly instead of duplicating the guidance and
      // "Proceed." that kickoff will supply.
      if (handoffPending) {
        const doing =
          target === "build"
            ? "Compacting the planning context and starting on the plan"
            : "Reviewing the branch before the MR";
        return {
          content: [
            {
              type: "text",
              text: `Approved. Switching to ${stage.label}. ${doing}\u2026`,
            },
          ],
          details: { stage: target, decision: "approved", note, handoff: true },
          terminate: true,
        };
      }

      const noteLine = note
        ? `\nThe user also added: "${note}". Factor this in.`
        : "";
      const guidance = await loadGuidance(ctx.cwd, workflow.id, target);
      return {
        content: [
          {
            type: "text",
            text: `Approved. Now in the ${stage.label} stage.${noteLine}\n\n${guidance}\n\nProceed.`,
          },
        ],
        details: { stage: target, decision: "approved", note },
      };
    },
  });
}
