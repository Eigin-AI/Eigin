/**
 * Plannotator integration — Plannotator as a review UI service.
 *
 * The stage extension owns the workflow; Plannotator only renders the review.
 * We talk to it over the shared event bus (`plannotator:request`) rather than
 * using its own plan-mode state machine.
 *
 * Two touchpoints:
 *  - submit_plan   → `plan-review` (asynchronous: result arrives on the
 *                    `plannotator:review-result` channel, handled by a listener)
 *  - submit_review → `code-review` (synchronous: Plannotator returns the result
 *                    directly once the user finishes, handled inline)
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const REQUEST_CHANNEL = "plannotator:request";
const RESULT_CHANNEL = "plannotator:review-result";

export const SUBMIT_PLAN_TOOL = "submit_plan";
export const SUBMIT_REVIEW_TOOL = "submit_review";

// Tracks the plan file path for each in-flight review (set by submit_plan,
// consumed by the review-result listener) and the most recently *approved*
// plan's path, exposed via getLastApprovedPlanPath() for the Plan→Build
// handoff (see index.ts / workflow/build-handoff.ts) to know which plan to
// inline into the Build kickoff message.
const pendingPlanPaths = new Map<string, string>();
let lastApprovedPlanPath: string | null = null;

/** The file path of the most recently approved plan, or null if none yet (or the last submission wasn't approved). */
export function getLastApprovedPlanPath(): string | null {
  return lastApprovedPlanPath;
}

/**
 * Register the Plannotator-backed plan and code review tools plus the
 * asynchronous plan-review result listener. Returns a cleanup function that
 * removes the listener; call it on `session_shutdown` so listeners don't stack
 * across reloads.
 */
export function registerPlannotator(pi: ExtensionAPI): () => void {
  registerSubmitPlan(pi);
  registerSubmitReview(pi);
  return registerReviewResultListener(pi);
}

function registerSubmitPlan(pi: ExtensionAPI): void {
  const schema = Type.Object({
    filePath: Type.String({ description: "Path to the plan markdown file" }),
  });

  pi.registerTool({
    name: SUBMIT_PLAN_TOOL,
    label: "Submit Plan",
    description:
      "Submit a plan for review. Opens a browser UI where the user can approve, deny with annotations, or approve with notes. " +
      "Use this in the PLAN stage after writing a detailed implementation plan to a markdown file. " +
      "The tool returns immediately; the user's decision arrives asynchronously.",
    promptSnippet: "Submit a plan markdown file for user review (browser UI)",
    promptGuidelines: [
      `Use ${SUBMIT_PLAN_TOOL} in the PLAN stage to submit your implementation plan for approval. Write the plan to a markdown file first, then submit it.`,
    ],
    parameters: schema,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const planPath = resolve(ctx.cwd, params.filePath);
      let planContent: string;

      try {
        planContent = await readFile(planPath, "utf-8");
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          content: [{ type: "text", text: `Failed to read plan file: ${msg}` }],
          details: { filePath: params.filePath, error: msg },
        };
      }

      const requestId = crypto.randomUUID();
      const response = await new Promise<unknown>((resolveResponse) => {
        pi.events.emit(REQUEST_CHANNEL, {
          requestId,
          action: "plan-review",
          payload: { planContent, planFilePath: planPath },
          respond: resolveResponse,
        });
      });

      const result = response as {
        status?: string;
        result?: { reviewId?: string; status?: string };
      };
      if (result.status === "handled" && result.result?.reviewId) {
        pendingPlanPaths.set(result.result.reviewId, planPath);
        return {
          content: [
            {
              type: "text",
              text: `Plan submitted for review (ID: ${result.result.reviewId}). The browser UI is now open. Awaiting the user's decision — stop and wait.`,
            },
          ],
          details: {
            filePath: params.filePath,
            reviewId: result.result.reviewId,
          },
          terminate: true,
        };
      }

      return {
        content: [
          {
            type: "text",
            text: "Plan submission failed — Plannotator may not be installed or responding. Check that the @plannotator/pi-extension is loaded.",
          },
        ],
        details: { filePath: params.filePath, response: result },
      };
    },
  });
}

function registerSubmitReview(pi: ExtensionAPI): void {
  const schema = Type.Object({
    diffType: Type.Optional(
      StringEnum(
        [
          "uncommitted",
          "staged",
          "unstaged",
          "last-commit",
          "branch",
          "since-base",
          "all",
        ],
        {
          description: "Which diff to review. Defaults to uncommitted changes.",
        },
      ),
    ),
    defaultBranch: Type.Optional(
      Type.String({
        description:
          "Base branch for 'branch' / 'since-base' / 'merge-base' diffs (e.g. main).",
      }),
    ),
  });

  pi.registerTool({
    name: SUBMIT_REVIEW_TOOL,
    label: "Submit Review",
    description:
      "Open the current git changes in a browser code-review UI. The user annotates specific lines and " +
      "approves or denies. Use this in the REVIEW stage. This tool blocks until the user finishes reviewing, " +
      "then returns their decision and line-level feedback inline — act on it in the same turn.",
    promptSnippet:
      "Open current git changes in a browser code-review UI (user annotates + approves)",
    promptGuidelines: [
      `Use ${SUBMIT_REVIEW_TOOL} in the REVIEW stage to have the user review your git changes. Address any returned feedback, then re-review or propose merge on approval.`,
    ],
    parameters: schema,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      // Code review is synchronous: Plannotator responds with the result once
      // the user finishes in the browser (unlike plan-review, no separate event).
      const requestId = crypto.randomUUID();
      const response = await new Promise<unknown>((resolveResponse) => {
        pi.events.emit(REQUEST_CHANNEL, {
          requestId,
          action: "code-review",
          payload: {
            cwd: ctx.cwd,
            diffType: params.diffType,
            defaultBranch: params.defaultBranch,
          },
          respond: resolveResponse,
        });
      });

      const res = response as {
        status?: string;
        error?: string;
        result?: { approved?: boolean; feedback?: string };
      };

      if (res.status !== "handled" || !res.result) {
        return {
          content: [
            {
              type: "text",
              text:
                `Code review could not start${res.error ? `: ${res.error}` : "."} ` +
                "Check that @plannotator/pi-extension is loaded and there are changes to review.",
            },
          ],
          details: { response: res },
        };
      }

      const feedback = res.result.feedback?.trim();
      const message = res.result.approved
        ? feedback
          ? `The changes were approved with notes:\n\n${feedback}\n\nAddress any notes, then propose moving to the merge stage.`
          : "The changes were approved. Propose moving to the merge stage."
        : feedback
          ? `The changes were not approved. Address this feedback and re-review:\n\n${feedback}`
          : "The changes were not approved. Revise and re-review.";

      return {
        content: [{ type: "text", text: message }],
        details: {
          approved: res.result.approved ?? false,
          diffType: params.diffType,
        },
      };
    },
  });
}

/**
 * Listen for asynchronous plan-review results and steer the agent to react.
 *
 * Reload-safe: `pi.events.on` returns an unsubscribe function that the caller
 * invokes on `session_shutdown` (fired on reload) so the old listener is removed
 * before the reloaded instance attaches a new one — otherwise listeners stack
 * and each reload adds another reaction to the same review. As a second guard we
 * dedupe by reviewId so a given review is only ever acted on once.
 */
function registerReviewResultListener(pi: ExtensionAPI): () => void {
  const handledReviews = new Set<string>();

  return pi.events.on(RESULT_CHANNEL, (event: unknown) => {
    const result = event as {
      reviewId?: string;
      approved?: boolean;
      feedback?: string;
    };

    if (result.reviewId) {
      if (handledReviews.has(result.reviewId)) return;
      handledReviews.add(result.reviewId);

      const planPath = pendingPlanPaths.get(result.reviewId);
      pendingPlanPaths.delete(result.reviewId);
      if (result.approved && planPath) lastApprovedPlanPath = planPath;
    }

    const feedback = result.feedback?.trim();
    const message = result.approved
      ? feedback
        ? `The plan was approved with notes:\n\n${feedback}\n\nPropose moving to the next stage, then execute the plan.`
        : "The plan was approved. Propose moving to the next stage, then execute the plan."
      : feedback
        ? `The plan was denied. Address this feedback and resubmit:\n\n${feedback}`
        : "The plan was denied. Revise and resubmit.";

    pi.sendUserMessage(message);
  });
}
