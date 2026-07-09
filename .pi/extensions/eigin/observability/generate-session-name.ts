/**
 * One-shot LLM call that turns a user message into a short session name (see
 * session-name.ts for the prompt/cleanup helpers). Best-effort: any failure
 * (no model, no API key, model error) resolves to undefined rather than
 * throwing, since this is a UX nicety and must never interrupt the agent
 * turn it's triggered from.
 */

import { complete } from "@earendil-works/pi-ai/compat";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { buildNamerPrompt, cleanSessionName } from "./session-name.ts";

/**
 * Generates a session name from the active model and the given source text
 * (the prompt to summarize), or undefined if unavailable or the call fails.
 */
export async function generateSessionName(
  ctx: ExtensionContext,
  sourceText: string,
): Promise<string | undefined> {
  const model = ctx.model;
  if (!model) return undefined;

  try {
    const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
    if (!auth.ok || !auth.apiKey) return undefined;

    const response = await complete(
      model,
      {
        messages: [
          {
            role: "user" as const,
            content: [{ type: "text" as const, text: buildNamerPrompt(sourceText) }],
            timestamp: Date.now(),
          },
        ],
      },
      { apiKey: auth.apiKey, headers: auth.headers, env: auth.env },
    );

    const raw = response.content
      .filter((c): c is { type: "text"; text: string } => c.type === "text")
      .map((c) => c.text)
      .join("\n");

    return cleanSessionName(raw);
  } catch {
    return undefined; // Best-effort — never let naming surface as an error to the user.
  }
}
