/** Behavioral panel tests with model calls faked at the provider boundary. */
import assert from "node:assert/strict";
import {
  cp,
  mkdtemp,
  mkdir,
  readFile,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { execFileSync } from "node:child_process";
import { registerPanel } from "./index.ts";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { join } from "node:path";
import { test } from "node:test";
import type { AssistantMessage, Context } from "@earendil-works/pi-ai";
import { loadMaterial } from "./material.ts";
import { loadPersonas } from "./profiles.ts";
import { emptyUsage, runPanel } from "./runner.ts";

const model = { provider: "fake", id: "reviewer", input: ["text", "image"] };
function response(
  text = "A grounded reaction",
  stopReason: AssistantMessage["stopReason"] = "stop",
): AssistantMessage {
  return {
    role: "assistant",
    api: "openai-completions",
    provider: "fake",
    model: "reviewer",
    content: [{ type: "text", text }],
    stopReason,
    timestamp: Date.now(),
    usage: { ...emptyUsage(), input: 10, output: 5, totalTokens: 15 },
  };
}
async function fixture(fn: (cwd: string) => Promise<void>) {
  const cwd = await mkdtemp(join(tmpdir(), "eigin-panel-"));
  try {
    await mkdir(join(cwd, ".pi/panel"), { recursive: true });
    await cp(
      new URL("../../../../panel/personas/", import.meta.url),
      join(cwd, ".pi/panel/personas"),
      { recursive: true },
    );
    await fn(cwd);
  } finally {
    await rm(cwd, { recursive: true, force: true });
  }
}

test("independent bounded reviews, synthesis, usage, and immutable snapshots", async () =>
  fixture(async (cwd) => {
    const calls: Context[] = [];
    let active = 0;
    let peak = 0;
    const report = await runPanel(
      { brief: "What does this offer?", text: "Your own AI" },
      {
        cwd,
        model,
        complete: async (context) => {
          calls.push(context);
          active++;
          peak = Math.max(peak, active);
          await new Promise((resolve) => setTimeout(resolve, 5));
          active--;
          return response();
        },
      },
    );
    assert.equal(report.status, "completed");
    assert.equal(calls.length, 6);
    assert.equal(peak, 3);
    const personas = await loadPersonas(cwd);
    for (const [i, context] of calls.slice(0, 5).entries()) {
      assert.equal(context.messages.length, 1);
      assert.equal(context.tools, undefined);
      const prompt = context.systemPrompt!;
      assert.ok(prompt.includes(personas[i].name));
      assert.ok(prompt.includes(personas[i].profile));
      assert.ok(!prompt.includes(personas[i].source.recordId));
      assert.ok(!prompt.includes(personas[i].source.dataset));
      assert.ok(!prompt.includes(personas[i].source.revision));
      for (const other of personas.filter((p) => p.id !== personas[i].id))
        assert.ok(!prompt.includes(other.profile));
      assert.ok(JSON.stringify(context.messages).includes("Your own AI"));
    }
    assert.equal(report.usage.totalTokens, 90);
    const inputPath = join(report.reportPath, "../input.json");
    const before = await readFile(inputPath, "utf8");
    await writeFile(join(cwd, ".pi/panel/personas/techie.md"), "{}");
    assert.equal(await readFile(inputPath, "utf8"), before);
    assert.match(
      await readFile(report.reportPath, "utf8"),
      /Simulated audience feedback/,
    );
  }));

test("explicit subset and individual failure retain completed responses", async () =>
  fixture(async (cwd) => {
    let count = 0;
    const contexts: Context[] = [];
    const report = await runPanel(
      { brief: "Explain", text: "copy", personaIds: ["techie", "manager"] },
      {
        cwd,
        model,
        complete: async (context) => {
          contexts.push(context);
          if (++count === 1) throw new Error("provider unavailable");
          return response();
        },
      },
    );
    assert.equal(report.status, "partial");
    assert.equal(report.reactions[0].status, "failed");
    assert.equal(report.reactions[1].status, "completed");
    assert.match(JSON.stringify(contexts.at(-1)), /provider unavailable/);
  }));

test("cancellation stops queued reviews and synthesis and saves progress", async () =>
  fixture(async (cwd) => {
    const abort = new AbortController();
    let calls = 0;
    const report = await runPanel(
      { brief: "Explain", text: "copy" },
      {
        cwd,
        model,
        complete: async () => {
          calls++;
          abort.abort();
          return response();
        },
      },
      abort.signal,
    );
    assert.equal(report.status, "cancelled");
    assert.equal(calls, 1);
    assert.equal(
      report.reactions.filter((r) => r.status === "cancelled").length,
      4,
    );
    assert.ok(await readFile(report.reportPath, "utf8"));
  }));

test("synthesis failure and incomplete provider output are visible", async () =>
  fixture(async (cwd) => {
    let calls = 0;
    const report = await runPanel(
      { brief: "Explain", text: "copy", personaIds: ["student"] },
      {
        cwd,
        model,
        complete: async () =>
          ++calls === 1 ? response() : response("cut off", "length"),
      },
    );
    assert.equal(report.status, "partial");
    assert.match(report.synthesisError!, /incomplete/);
    assert.equal(report.usage.totalTokens, 30);
  }));

test("validation fails before inference for invalid inputs and profiles", async () =>
  fixture(async (cwd) => {
    let calls = 0;
    const deps = {
      cwd,
      model,
      complete: async () => {
        calls++;
        return response();
      },
    };
    for (const request of [
      { brief: "Explain" },
      { brief: "Explain", text: "copy", personaIds: ["missing"] },
      { brief: "Explain", text: "copy", personaIds: ["student", "student"] },
      { brief: "Explain", text: "x".repeat(102401) },
    ])
      await assert.rejects(runPanel(request, deps));
    await writeFile(join(cwd, ".pi/panel/personas/student.md"), "{}");
    await assert.rejects(
      runPanel({ brief: "Explain", text: "copy" }, deps),
      /Invalid panel profile/,
    );
    assert.equal(calls, 0);
  }));

test("text and image snapshots reach the provider intact; invalid material is rejected", async () =>
  fixture(async (cwd) => {
    const png = Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC",
      "base64",
    );
    await writeFile(join(cwd, "art.png"), png);
    await writeFile(join(cwd, "copy.md"), "Hello æøå");
    const material = await loadMaterial(
      cwd,
      { brief: "Look", files: ["art.png", "copy.md"] },
      true,
    );
    assert.equal(
      material.content.find((c) => c.type === "image")?.data,
      png.toString("base64"),
    );
    assert.match(JSON.stringify(material.content), /Hello æøå/);
    await assert.rejects(
      loadMaterial(cwd, { brief: "Look", files: ["art.png"] }, false),
      /does not support images/,
    );
    await writeFile(join(cwd, "truncated.png"), png.subarray(0, 24));
    await assert.rejects(
      loadMaterial(cwd, { brief: "Look", files: ["truncated.png"] }, true),
      /cannot be decoded/,
    );
    await writeFile(join(cwd, "bad.png"), "not an image");
    await assert.rejects(
      loadMaterial(cwd, { brief: "Look", files: ["bad.png"] }, true),
      /Unsupported/,
    );
    await assert.rejects(
      loadMaterial(
        cwd,
        { brief: "Look", files: ["https://example.com"] },
        true,
      ),
      /local files/,
    );
    await assert.rejects(
      loadMaterial(cwd, { brief: "Look", files: ["."] }, true),
    );
    await writeFile(join(cwd, "bad.txt"), Buffer.from([255, 255]));
    await assert.rejects(
      loadMaterial(cwd, { brief: "Look", files: ["bad.txt"] }, true),
    );
  }));

test("outside paths, symlink escapes, special files, and cancellation are rejected", async () =>
  fixture(async (cwd) => {
    const outside = await mkdtemp(join(tmpdir(), "eigin-outside-"));
    try {
      await writeFile(join(outside, "secret.txt"), "private");
      await symlink(join(outside, "secret.txt"), join(cwd, "escape.txt"));
      for (const path of [join(outside, "secret.txt"), "escape.txt"])
        await assert.rejects(
          loadMaterial(cwd, { brief: "Look", files: [path] }, true),
          /inside the workspace/,
        );
      if (process.platform !== "win32") {
        execFileSync("mkfifo", [join(cwd, "pipe.txt")]);
        await assert.rejects(
          loadMaterial(cwd, { brief: "Look", files: ["pipe.txt"] }, true),
          /regular file/,
        );
      }
      const abort = new AbortController();
      abort.abort();
      await assert.rejects(
        loadMaterial(cwd, { brief: "Look", text: "copy" }, true, abort.signal),
      );
    } finally {
      await rm(outside, { recursive: true, force: true });
    }
  }));

test("runtime model extras are never serialized", async () =>
  fixture(async (cwd) => {
    const report = await runPanel(
      { brief: "Look", text: "copy", personaIds: ["student"] },
      {
        cwd,
        model: {
          ...model,
          headers: { Authorization: "secret-token" },
        } as typeof model,
        complete: async () => response(),
      },
    );
    const input = await readFile(
      join(report.reportPath, "../input.json"),
      "utf8",
    );
    assert.ok(!input.includes("secret-token"));
    assert.deepEqual(JSON.parse(input).model, {
      provider: "fake",
      id: "reviewer",
    });
  }));

test("command and tool share the registered review entry point", async () => {
  const tools: string[] = [];
  const commands = new Map();
  const messages: string[] = [];
  registerPanel({
    registerTool: (tool: { name: string }) => tools.push(tool.name),
    registerCommand: (name: string, command: unknown) =>
      commands.set(name, command),
    sendUserMessage: (message: string) => messages.push(message),
  } as unknown as ExtensionAPI);
  assert.deepEqual(tools, ["review_panel"]);
  assert.deepEqual([...commands.keys()], ["eigin:panel"]);
  await commands.get("eigin:panel").handler("What does this mean?", {});
  assert.match(messages[0], /review_panel/);
  assert.match(messages[0], /Ask for missing material/);
  const notifications: string[] = [];
  await commands.get("eigin:panel").handler("", {
    cwd: process.cwd(),
    ui: { notify: (message: string) => notifications.push(message) },
  });
  assert.match(notifications[0], /techie/);
});

test("synthesis is preserved with attributed quotes and one report-level disclaimer", async () =>
  fixture(async (cwd) => {
    let calls = 0;
    const synthesis =
      "### Highlights\n- techie: “Useful for drafts.”\n\n### Agreements\n- techie and manager want review before sharing.\n\n### Disagreements\n- None expressed.\n\n### Potential action items\n- Consider making draft review explicit.\n\n### Potential follow-ups with real users\n- Ask someone to check a draft before sharing it.";
    const report = await runPanel(
      {
        brief: "What stands out?",
        text: "Draft and review",
        personaIds: ["techie", "manager"],
      },
      {
        cwd,
        model,
        complete: async () =>
          response(++calls <= 2 ? "Useful for drafts." : synthesis),
      },
    );
    const saved = await readFile(report.reportPath, "utf8");
    assert.equal(report.synthesis, synthesis);
    assert.ok(saved.includes(synthesis));
    assert.equal(saved.split("Simulated feedback:").length - 1, 1);
    const input = JSON.parse(
      await readFile(join(report.reportPath, "../input.json"), "utf8"),
    );
    assert.ok(Number.isInteger(input.promptVersion) && input.promptVersion > 0);
  }));
