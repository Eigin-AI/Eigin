/**
 * Herdr blocked-state signalling.
 *
 * Herdr (a multi-terminal agent orchestrator) shows each pane as working,
 * idle, or blocked. Pi's official Herdr integration
 * (`herdr integration install pi`) derives working/idle from the agent
 * lifecycle and overlays `blocked` whenever it receives a `herdr:blocked`
 * event on Pi's shared event bus — using a balanced counter, so nested blocks
 * work. That integration is the single consumer that talks to Herdr; here we
 * only emit the event.
 *
 * We emit `blocked` around our own human-in-the-loop dialogs (propose_stage,
 * wait_for_user, ask_questions, the model-switch and Plan→Build confirms, the
 * fresh-session workflow picker) so a pane parked on one of those reads as
 * "needs a decision" in the Herdr sidebar instead of idle. The
 * `@aliou/pi-guardrails` package already emits the same event for its approval
 * prompts, so those are covered independently.
 *
 * Emitting is a no-op when the integration isn't installed (nothing listens to
 * the event), so this stays a soft dependency: no `herdr` binary is invoked
 * and no lifecycle reporting is reimplemented here.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const HERDR_BLOCKED_EVENT = "herdr:blocked";

/** Tell Herdr a pane is (un)blocked waiting on a user decision. */
export function emitHerdrBlocked(pi: ExtensionAPI, active: boolean, label?: string): void {
  pi.events.emit(HERDR_BLOCKED_EVENT, active ? { active: true, label } : { active: false });
}

/**
 * Run a dialog while reporting the pane as blocked in Herdr. The unblock fires
 * in a `finally`, so a cancelled or throwing dialog still balances the
 * integration's block counter.
 */
export async function withHerdrBlocked<T>(
  pi: ExtensionAPI,
  label: string,
  run: () => Promise<T>,
): Promise<T> {
  emitHerdrBlocked(pi, true, label);
  try {
    return await run();
  } finally {
    emitHerdrBlocked(pi, false);
  }
}
