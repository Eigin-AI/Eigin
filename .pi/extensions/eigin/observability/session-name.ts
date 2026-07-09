/**
 * Pure helpers for generating and cleaning a session name.
 *
 * Session names go through pi.setSessionName(), not ctx.ui.setTitle():
 * pi's own interactive-mode UpdateTerminalTitle() re-sends `<app> - <name> -
 * <cwd>` as an OSC 2 title on every session_start/session_info_changed,
 * which always wins the race against a custom ctx.ui.setTitle() call. Naming
 * through pi.setSessionName() feeds that title update directly, and also
 * renames the session in /resume lists — the actual mechanism this project
 * wants for cross-session observability, not just a terminal title.
 */

const MAX_NAME_LENGTH = 50;

type ContentBlock = { type?: string; text?: string };
type SessionEntry = { type: string; message?: { role?: string; content?: unknown } };

/** Prompt asking the model for a short, human-readable session name. */
export function buildNamerPrompt(userText: string): string {
  return [
    "You are naming a coding session based on the user's message below.",
    "",
    "Rules:",
    "- Output in the SAME language as the user's message",
    `- Maximum ${MAX_NAME_LENGTH} characters`,
    "- Output ONLY the name, no quotes, no prefix, no explanation",
    "- Summarize intent, don't copy the message verbatim",
    "- Keep specific file/module/function names if the message mentions them",
    "- Be specific: \"Fix auth token refresh bug\" beats \"Fix a bug\"",
    "",
    "<message>",
    userText,
    "</message>",
  ].join("\n");
}

const QUOTE_PAIRS: Array<[string, string]> = [
  ['"', '"'],
  ["'", "'"],
  ["`", "`"],
  ["「", "」"],
];

/**
 * Normalizes a raw model completion into a clean session name: strips a
 * matching pair of surrounding quotes, collapses to a single line, and
 * truncates with an ellipsis. Returns undefined if nothing usable survives.
 */
export function cleanSessionName(raw: string): string | undefined {
  let name = raw.split("\n")[0]?.trim() ?? "";

  for (const [open, close] of QUOTE_PAIRS) {
    if (name.length > open.length + close.length && name.startsWith(open) && name.endsWith(close)) {
      name = name.slice(open.length, name.length - close.length).trim();
      break;
    }
  }

  if (name.length > MAX_NAME_LENGTH) {
    name = `${name.slice(0, MAX_NAME_LENGTH - 1).trimEnd()}…`;
  }

  return name.length > 0 ? name : undefined;
}

function extractText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((part): part is ContentBlock => !!part && typeof part === "object")
    .filter((part) => part.type === "text" && typeof part.text === "string")
    .map((part) => part.text as string)
    .join("\n");
}

/**
 * Most recent non-empty user message in the branch (for manual /rename),
 * scanning from the end so a mid-session rename reflects current focus
 * rather than the session's original opening message.
 */
export function extractLastUserText(entries: SessionEntry[]): string | undefined {
  for (let i = entries.length - 1; i >= 0; i--) {
    const entry = entries[i];
    if (entry?.type !== "message" || entry.message?.role !== "user") continue;
    const text = extractText(entry.message.content).trim();
    if (text.length > 0) return text;
  }
  return undefined;
}
