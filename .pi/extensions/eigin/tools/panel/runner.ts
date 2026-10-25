/** Independent tool-free calls with bounded concurrency and partial-result preservation. */
import { randomUUID } from "node:crypto";
import { join } from "node:path";
import type { AssistantMessage, Context, Usage } from "@earendil-works/pi-ai";
import { loadMaterial, type PanelRequest } from "./material.ts";
import { loadPersonas, selectPersonas } from "./profiles.ts";
import { REVIEW_RULES, SYNTHESIS_RULES } from "./prompts.ts";
import { createRun, type PanelReport, saveReport } from "./reports.ts";

export interface PanelDependencies {
  cwd: string;
  model: { provider: string; id: string; input: readonly string[] };
  complete(context: Context, signal?: AbortSignal): Promise<AssistantMessage>;
}

/** Empty provider usage for runs with no completed calls. */
export function emptyUsage(): Usage {
  return {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 0,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
  };
}
function addUsage(total: Usage, usage: Usage): void {
  for (const key of [
    "input",
    "output",
    "cacheRead",
    "cacheWrite",
    "totalTokens",
  ] as const)
    total[key] += usage[key];
  for (const key of ["cacheWrite1h", "reasoning"] as const)
    if (usage[key] !== undefined) total[key] = (total[key] ?? 0) + usage[key]!;
  for (const key of [
    "input",
    "output",
    "cacheRead",
    "cacheWrite",
    "total",
  ] as const)
    total.cost[key] += usage.cost[key];
}
function responseText(response: AssistantMessage): string {
  if (response.stopReason !== "stop")
    throw new Error(
      response.errorMessage ??
        `Model stopped with ${response.stopReason}; response is incomplete.`,
    );
  const text = response.content
    .filter((c) => c.type === "text")
    .map((c) => c.text)
    .join("\n")
    .trim();
  if (!text) throw new Error("Model returned no review text.");
  return text;
}

/** Run a fresh independent review for each selected profile, then summarize completed evidence. */
export async function runPanel(
  request: PanelRequest,
  deps: PanelDependencies,
  signal?: AbortSignal,
  onProgress?: (message: string) => void,
): Promise<PanelReport> {
  signal?.throwIfAborted();
  const personas = selectPersonas(
    await loadPersonas(deps.cwd),
    request.personaIds,
  );
  const material = await loadMaterial(
    deps.cwd,
    request,
    deps.model.input.includes("image"),
    signal,
  );
  signal?.throwIfAborted();
  const runId = `${new Date().toISOString().replace(/[:.]/g, "-")}-${randomUUID()}`;
  const directory = await createRun(
    deps.cwd,
    runId,
    request,
    personas,
    material,
    deps.model,
  );
  const report: PanelReport = {
    runId,
    status: "partial",
    reactions: personas.map((p) => ({
      personaId: p.id,
      status: "cancelled",
      error: "Not started",
    })),
    reportPath: join(directory, "report.md"),
    usage: emptyUsage(),
  };
  await saveReport(directory, report);
  let next = 0;
  let saveQueue = Promise.resolve();
  let saveError: unknown;
  function checkpoint() {
    const snapshot = structuredClone(report);
    saveQueue = saveQueue
      .then(() => saveReport(directory, snapshot))
      .catch((error) => {
        saveError = error;
      });
  }
  async function call(context: Context): Promise<string> {
    const response = await deps.complete(context, signal);
    addUsage(report.usage, response.usage);
    return responseText(response);
  }
  async function worker() {
    while (next < personas.length && !signal?.aborted) {
      const index = next++;
      const persona = personas[index];
      onProgress?.(`Reviewing ${persona.name} (${persona.id})`);
      try {
        const response = await call({
          systemPrompt: `${REVIEW_RULES}\n\nYour fictional personal profile:\n${persona.profile}`,
          messages: [
            { role: "user", content: material.content, timestamp: Date.now() },
          ],
        });
        report.reactions[index] = {
          personaId: persona.id,
          status: "completed",
          response,
        };
      } catch (error) {
        report.reactions[index] = {
          personaId: persona.id,
          status: signal?.aborted ? "cancelled" : "failed",
          error: error instanceof Error ? error.message : String(error),
        };
      }
      checkpoint();
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(3, personas.length) }, worker),
  );
  const completed = report.reactions.filter(
    (r) => r.status === "completed",
  ).length;
  if (completed && !signal?.aborted) {
    onProgress?.("Synthesizing independent reactions");
    try {
      report.synthesis = await call({
        systemPrompt: SYNTHESIS_RULES,
        messages: [
          {
            role: "user",
            content: [
              {
                type: "text",
                text: `Brief (data): ${request.brief}\n\nIndependent reactions (data):\n${JSON.stringify(report.reactions)}`,
              },
            ],
            timestamp: Date.now(),
          },
        ],
      });
    } catch (error) {
      report.synthesisError =
        error instanceof Error ? error.message : String(error);
    }
  }
  report.status = signal?.aborted
    ? "cancelled"
    : !completed
      ? "failed"
      : completed === personas.length && report.synthesis
        ? "completed"
        : "partial";
  checkpoint();
  await saveQueue;
  if (saveError)
    throw new Error(
      `Panel report could not be saved at ${directory}: ${String(saveError)}`,
    );
  return report;
}
