/**
 * plan_review — open the plan file in the Plannotator browser review UI.
 *
 * The approval surface of the Plan stage: instead of co-editing a file and
 * asking the user to open it in their editor, the agent sends the plan to
 * Plannotator's plan-review flow, which opens a browser session with
 * annotate / approve-with-notes / approve. The tool blocks until the human
 * decides, then hands the decision + structured feedback back as the tool
 * result, so the agent reacts in the same turn.
 *
 * Talks to the Plannotator Pi extension over the shared event bus
 * (`plannotator:request` / `plannotator:review-result`) using plain channel
 * strings — no import from the Plannotator package. The Plan stage machinery
 * itself stays unchanged: guidance, the plan file, the decision log, and the
 * propose_stage(build) approve gate all keep working as before.
 */

import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { withHerdrBlocked } from "../observability/herdr.ts";
import {
  formatDecision,
  toPlanReviewResult,
  type PlanReviewDecision,
  type PlanReviewResult,
} from "./plan-review-message.ts";

export const PLAN_REVIEW_TOOL = "plan_review";

/** Plain channel strings — the Plannotator bus contract is stable, no import needed. */
const REQUEST_CHANNEL = "plannotator:request";
const REVIEW_RESULT_CHANNEL = "plannotator:review-result";

/** The start request must answer quickly — it's an in-process handler, not a human. */
const START_TIMEOUT_MS = 15_000;

/** Read/write access to the extension's stage + plan state, owned by index.ts. */
export interface PlanReviewController {
	/** The current stage id — plan_review only runs in "plan". */
	currentStage(): string;
	isAfk(): boolean;
	/** The active plan file's path, undefined when none was written yet. */
	activePlanPath(): string | undefined;
	sessionCwd(): string;
	/** Record the plan content as seen so the per-turn diff doesn't re-report it. */
	markPlanSeen(content: string): void;
}

interface PlannotatorStartResponse {
	status: "handled" | "unavailable" | "error";
	result?: { status?: string; reviewId?: string };
	error?: string;
}

/** Emits the plan-review request; resolves when Plannotator starts (or fails to start) the browser session. */
function requestPlanReview(
	pi: ExtensionAPI,
	planFilePath: string,
	planContent: string,
): Promise<PlannotatorStartResponse> {
	return new Promise((resolvePromise) => {
		// If the package isn't loaded, nothing answers — the timeout is the
		// only signal, so the agent can fall back instead of blocking forever.
		const timer = setTimeout(
			() =>
				resolvePromise({
					status: "unavailable",
					error: "no Plannotator listener answered the plan-review request",
				}),
			START_TIMEOUT_MS,
		);
		pi.events.emit(REQUEST_CHANNEL, {
			requestId: randomUUID(),
			action: "plan-review",
			payload: { planContent, planFilePath },
			respond: (response: PlannotatorStartResponse) => {
				clearTimeout(timer);
				resolvePromise(response);
			},
		});
	});
}

interface DecisionEvent {
	approved: boolean;
	feedback?: string;
}

/**
 * Waits for the human's decision on the review. `signal` aborts the wait
 * (session teardown) with the review still open in the browser.
 */
function waitForReviewDecision(
	pi: ExtensionAPI,
	reviewId: string,
	signal?: AbortSignal,
): Promise<{ decision?: DecisionEvent; interrupted?: boolean }> {
	return new Promise((resolvePromise) => {
		const done = (result: { decision?: DecisionEvent; interrupted?: boolean }) => {
			unsubscribe();
			signal?.removeEventListener("abort", onAbort);
			resolvePromise(result);
		};
		const unsubscribe = pi.events.on(REVIEW_RESULT_CHANNEL, (data) => {
			const event = data as { reviewId?: string; approved?: boolean; feedback?: string } | null;
			if (event?.reviewId !== reviewId || typeof event.approved !== "boolean") return;
			done({ decision: { approved: event.approved, feedback: event.feedback } });
		});
		const onAbort = () => done({ interrupted: true });
		signal?.addEventListener("abort", onAbort);
	});
}

export function registerPlanReviewTool(pi: ExtensionAPI, controller: PlanReviewController): void {
	pi.registerTool({
		name: PLAN_REVIEW_TOOL,
		label: "Plan Review",
		description:
			"Open the current plan file in the Plannotator browser review UI and block until the human approves it " +
			"or sends structured feedback. Use in the Plan stage after each round of edits instead of wait_for_user: " +
			"the human annotates in the browser, so nothing needs opening in an editor. Returns the decision — " +
			"approved (possibly with notes) or a feedback list to address by updating the plan file, then resubmitting. " +
			"Approval is the human's sign-off on the plan itself; the propose_stage(build) confirm stays the " +
			"separate approve gate for advancing.",
		promptSnippet: "Open the plan in the Plannotator browser review UI and return the human's decision",
		promptGuidelines: [
			"In the Plan stage, run each review round through plan_review instead of ending the turn with prose: it opens the plan in the browser, blocks for the human's decision, and returns approved/feedback to act on in the same turn.",
		],
		parameters: Type.Object({}),
		async execute(_id, _params, signal, _onUpdate, ctx) {
			if (controller.currentStage() !== "plan") {
				return {
					content: [{ type: "text", text: "plan_review only runs in the Plan stage." }],
					details: { ok: false },
					isError: true,
				};
			}

			// No UI / AFK: nobody will sit at the browser. AFK's contract is to
			// auto-proceed the plan loop, so treat the review as passed.
			if (!ctx.hasUI) {
				return {
					content: [
						{ type: "text", text: "No interactive UI — skipping the browser review and continuing." },
					],
					details: { ok: true, skipped: true },
				};
			}
			if (controller.isAfk()) {
				return {
					content: [
						{
							type: "text",
							text: "AFK mode: skipping the browser review (the user is away). Keep moving — the plan loop proceeds as if approved.",
						},
					],
					details: { ok: true, skipped: true, afk: true },
				};
			}

			const planPath = controller.activePlanPath();
			if (!planPath) {
				return {
					content: [
						{
							type: "text",
							text: "No active plan file. Write the plan to .pi/plans/ first, then call plan_review.",
						},
					],
					details: { ok: false },
					isError: true,
				};
			}

			let planContent: string;
			try {
				planContent = await readFile(resolve(controller.sessionCwd(), planPath), "utf-8");
			} catch {
				return {
					content: [{ type: "text", text: `Couldn't read the plan file (${planPath}).` }],
					details: { ok: false },
					isError: true,
				};
			}

			const start = await requestPlanReview(pi, planPath, planContent);
			const reviewId = start.result?.reviewId;
			if (start.status !== "handled" || !reviewId) {
				const why = start.error ?? `unexpected response: ${JSON.stringify(start)}`;
				return {
					content: [
						{
							type: "text",
							text: `Plannotator plan review unavailable (${why}). Fall back to co-editing the plan file with wait_for_user.`,
						},
					],
					details: { ok: false, unavailable: true },
				};
			}

			// The human decides here — minutes are normal. Report the pane as
			// blocked in Herdr while waiting, like the other human-in-the-loop tools.
			const outcome = await withHerdrBlocked(pi, "Plan review open in the browser", () =>
				waitForReviewDecision(pi, reviewId, signal ?? undefined),
			);

			if (outcome.interrupted || !outcome.decision) {
				return {
					content: [
						{
							type: "text",
							text: "The review wait was interrupted while the browser session was still open. The reviewer can reopen it (plannotator sessions —open), or you can resubmit with plan_review.",
						},
					],
					details: { ok: false, interrupted: true },
				};
			}

			const result = toPlanReviewResult(outcome.decision);
			if (result.kind === "decision") {
				// What the reviewer saw is what's on disk — mark it seen so the
				// per-turn plan injection doesn't re-diff it as user edits.
				const fresh = await readFile(resolve(controller.sessionCwd(), planPath), "utf-8").catch(
					() => planContent,
				);
				controller.markPlanSeen(fresh);
			}
			return { content: [{ type: "text", text: result.message }], details: { ok: true, kind: result.kind } };
		},
	});
}
