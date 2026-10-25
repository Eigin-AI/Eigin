/** Local review artifacts contain private supplied content and are excluded from git. */
import { mkdir, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { Usage } from "@earendil-works/pi-ai";
import type { MaterialSnapshot, PanelRequest } from "./material.ts";
import type { Persona } from "./profiles.ts";
import { PROMPT_VERSION } from "./prompts.ts";

export interface PanelReaction {
  personaId: string;
  status: "completed" | "failed" | "cancelled";
  response?: string;
  error?: string;
}
export interface PanelReport {
  runId: string;
  status: "completed" | "partial" | "cancelled" | "failed";
  reactions: PanelReaction[];
  synthesis?: string;
  synthesisError?: string;
  reportPath: string;
  usage: Usage;
}

/** Render individual responses without collapsing differences into the synthesis. */
export function renderReport(report: PanelReport): string {
  return [
    `# Simulated audience feedback`,
    `Status: ${report.status}`,
    `Simulated feedback: treat it as hypotheses, not evidence of real-user behavior.`,
    ...report.reactions.map(
      (r) =>
        `## ${r.personaId} — ${r.status}\n\n${r.response ?? r.error ?? "No response"}`,
    ),
    `## Synthesis\n\n${report.synthesis ?? report.synthesisError ?? "Not available"}`,
  ].join("\n\n");
}

/** Snapshot explicit material and profiles before starting any paid calls. */
export async function createRun(
  cwd: string,
  runId: string,
  request: PanelRequest,
  personas: Persona[],
  material: MaterialSnapshot,
  model: { provider: string; id: string },
): Promise<string> {
  const directory = join(cwd, ".pi/panel/runs", runId);
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const files = [];
  for (const file of material.files) {
    await writeFile(join(directory, file.name), file.bytes, {
      mode: 0o600,
      flag: "wx",
    });
    const { bytes: _bytes, ...metadata } = file;
    files.push(metadata);
  }
  await writeFile(
    join(directory, "input.json"),
    JSON.stringify(
      {
        runId,
        startedAt: new Date().toISOString(),
        promptVersion: PROMPT_VERSION,
        model: { provider: model.provider, id: model.id },
        request,
        personas,
        files,
      },
      null,
      2,
    ),
    { mode: 0o600, flag: "wx" },
  );
  return directory;
}

/** Atomically replace machine-readable progress and the readable report. */
export async function saveReport(
  directory: string,
  report: PanelReport,
): Promise<void> {
  for (const [name, content] of [
    [
      "report.json",
      JSON.stringify(
        { ...report, updatedAt: new Date().toISOString() },
        null,
        2,
      ),
    ],
    ["report.md", renderReport(report)],
  ]) {
    await writeFile(join(directory, `${name}.tmp`), content, { mode: 0o600 });
    await rename(join(directory, `${name}.tmp`), join(directory, name));
  }
}
