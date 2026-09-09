/**
 * AFK (away-from-keyboard) mode state.
 *
 * When on, AFK auto-proceeds the extension's own human-in-the-loop dialogs so
 * the agent never blocks waiting on the user — stage transitions (including
 * into Merge), the role's model switch, plan→build compaction, pre-merge
 * review, ask_questions (picks the recommended option), and wait_for_user
 * (signals ready immediately). Dangerous commands that guardrails would
 * otherwise prompt on are blocked separately (see afk-block.ts).
 *
 * Pure state plus accessors; persistence and the toggle command live in
 * index.ts, same pattern as the workflow/stage and task-list state.
 */

export interface AfkState {
  enabled: boolean;
}

/** The default — AFK off — so a brand-new session is attended. */
export function emptyAfk(): AfkState {
  return { enabled: false };
}

export function isAfk(state: AfkState): boolean {
  return state.enabled;
}

/** Set AFK on or off. The value is absolute, so the prior state isn't needed. */
export function setAfk(enabled: boolean): AfkState {
  return { enabled };
}

/** Flip AFK on or off. */
export function toggleAfk(state: AfkState): AfkState {
  return { enabled: !state.enabled };
}
