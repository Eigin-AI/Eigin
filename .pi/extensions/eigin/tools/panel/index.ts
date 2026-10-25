/** On-demand synthetic audience reviews, available throughout the existing workflow. */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { loadPersonas } from "./profiles.ts";
import { renderReport } from "./reports.ts";
import { runPanel } from "./runner.ts";

export const PANEL_TOOL = "review_panel";

/** Register the review tool and a thin command entry point using the same execution path. */
export function registerPanel(pi: ExtensionAPI): void {
  pi.registerTool({
    name: PANEL_TOOL,
    label: "Virtual Panel",
    description:
      "Review explicit text and local text/image files with independent synthetic Danish audience personas. Returns individual reactions, a synthesis, and a saved local report. This sends supplied material to the current model provider and writes private artifacts under .pi/panel/runs/. No browsing or session history is supplied. Feedback is simulated hypotheses, not real-user evidence. Available persona IDs: techie, nontechnical, small-team, manager, student. Use /eigin:panel to list current profiles.",
    promptGuidelines: [
      "Use a neutral brief. Send only explicitly selected material; never include conversation history or internal design rationale by default. Ask for missing material rather than guessing. Synthetic feedback cannot validate real audience behavior.",
    ],
    parameters: Type.Object({
      brief: Type.String({
        minLength: 1,
        description:
          "Neutral task or question, without the team's preferred answer.",
      }),
      personaIds: Type.Optional(
        Type.Array(Type.String(), {
          minItems: 1,
          maxItems: 5,
          uniqueItems: true,
        }),
      ),
      text: Type.Optional(
        Type.String({
          description: "Supplied copy or material, not conversation history.",
        }),
      ),
      files: Type.Optional(
        Type.Array(Type.String(), {
          maxItems: 10,
          description:
            "Explicit local text or PNG/JPEG/WebP/GIF paths, inside the workspace; relative or absolute workspace paths.",
        }),
      ),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      const model = ctx.model;
      if (!model) throw new Error("Select a model before running the panel.");
      if (!ctx.modelRegistry.hasConfiguredAuth(model))
        throw new Error("The selected model has no configured authentication.");
      const report = await runPanel(
        params,
        {
          cwd: ctx.cwd,
          model,
          complete: (context, abort) =>
            ctx.modelRegistry
              .streamSimple(model, context, { signal: abort, maxTokens: 2000 })
              .result(),
        },
        signal,
        (message) =>
          onUpdate?.({
            content: [{ type: "text", text: message }],
            details: undefined,
          }),
      );
      const text = renderReport(report);
      return {
        content: [
          {
            type: "text",
            text: `${text.length > 24000 ? `${text.slice(0, 24000)}\n\n[Truncated; read the saved report for all responses.]` : text}\n\nSaved report: ${report.reportPath}`,
          },
        ],
        details: report,
        usage: report.usage,
        isError: report.status === "failed",
      };
    },
  });
  pi.registerCommand("eigin:panel", {
    description:
      "Review supplied material with the virtual audience panel, or list personas",
    handler: async (args, ctx) => {
      if (!args.trim()) {
        try {
          const personas = await loadPersonas(ctx.cwd);
          ctx.ui.notify(
            `Usage: /eigin:panel <neutral review brief>\nChoose supplied text or local images/files with the assistant.\n${personas.map((p) => `${p.id}: ${p.name} — ${p.description}`).join("\n")}\nReviews send material to the current model provider and save private local reports.`,
            "info",
          );
        } catch (error) {
          ctx.ui.notify(String(error), "error");
        }
        return;
      }
      pi.sendUserMessage(
        `Prepare a review_panel call for this user request: ${JSON.stringify(args)}. Use explicitly selected text or local files only. Ask for missing material; do not send our conversation or design rationale. Use a neutral brief. Explain that supplied material goes to the current model provider and reports are saved locally.`,
        { deliverAs: "followUp" },
      );
    },
  });
}
