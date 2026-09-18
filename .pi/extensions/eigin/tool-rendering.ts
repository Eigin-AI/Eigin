/**
 * Compact rendering for pi's built-in tools.
 *
 * Collapsed tool results cost the same screen estate whether they carry one
 * line or one hundred, and the agent issues dozens per turn — so collapsed
 * output becomes one summary line plus at most a couple of tail lines, and
 * long commands get cut to terminal width instead of wrapping. `ctrl+o` still
 * expands everything, and execution is delegated untouched to the built-in
 * tools, so what the model sees doesn't change.
 *
 * Pattern per pi's `examples/extensions/built-in-tool-renderer.ts`: re-register
 * the tool by name, delegate `execute` to the created original, replace
 * `renderCall`/`renderResult`. Duration is measured in the delegation wrapper
 * (details carry everything else) and stashed as an extra details field.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	createBashTool,
	createEditTool,
	createFindTool,
	createGrepTool,
	createLsTool,
	createReadTool,
	createWriteTool,
	type BashToolDetails,
	type EditToolDetails,
	type GrepToolDetails,
	type LsToolDetails,
} from "@earendil-works/pi-coding-agent";
import { resolve } from "node:path";
import { readFileSync } from "node:fs";
import { truncateToWidth } from "@earendil-works/pi-tui";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

type Args = Record<string, unknown>;

/**
 * The slice of pi's global settings that tool construction forwards: the
 * built-ins pi registers itself get shellPath/commandPrefix/image settings
 * from here; our delegates must match.
 */
interface PiToolSettings {
	shellPath?: string;
	shellCommandPrefix?: string;
	imageAutoResize?: boolean;
}

function readToolSettings(cwd: string): PiToolSettings {
	// Project settings merge over global, same as pi's settings-manager; ~ in
	// shellPath expands against the project cwd.
	let merged: {
		shellPath?: string;
		shellCommandPrefix?: string;
		images?: { autoResize?: boolean };
	} = {};
	for (const path of [resolve(getAgentDir(), "settings.json"), resolve(cwd, ".pi/settings.json")]) {
		try {
			const raw = JSON.parse(readFileSync(path, "utf8")) as typeof merged;
			merged = { ...merged, ...raw };
		} catch {
			// Missing/unreadable file — keep what earlier scopes set.
		}
	}
	return {
		shellPath: merged.shellPath,
		shellCommandPrefix: merged.shellCommandPrefix,
		imageAutoResize: merged.images?.autoResize,
	};
}

/** Lines render width-truncated, never wrapped onto continuation lines. */
function linesComponent(lines: string[]): {
	render: (width: number) => string[];
	invalidate: () => void;
} {
	return {
		render: (width: number) => lines.map((l) => truncateToWidth(l, width)),
		invalidate: () => {},
	};
}

function str(args: Args, key: string): string {
	const value = args[key];
	return typeof value === "string" ? value : "";
}

/**
 * Strip pi's bash status footer from raw output. Non-zero exits throw with
 * `\n\nCommand exited with code N` appended (which lands here as the error
 * toolResult's text); timeouts append `Command timed out after N seconds`.
 */
function splitBashOutput(output: string): { body: string; exitCode: number | undefined } {
	const exit = output.match(/\n*Command exited with code (\d+)\s*$/);
	if (exit) return { body: output.slice(0, exit.index).trimEnd(), exitCode: Number(exit[1]) };
	const legacy = output.match(/\n*\[?exit code: (\d+)\]?\s*$/i);
	if (legacy) return { body: output.slice(0, legacy.index).trimEnd(), exitCode: Number(legacy[1]) };
	return { body: output.trimEnd(), exitCode: undefined };
}

function text(output: unknown): string {
	const parts = Array.isArray(output) ? output : [];
	return parts
		.map((c) => (typeof c === "object" && c !== null && "text" in c ? String((c as { text: unknown }).text) : ""))
		.join("");
}

function nonEmptyLines(output: string): string[] {
	return output.split("\n").filter((l) => l.trim() !== "");
}

/** Compact counters for collapsed footers. */
function formatCount(n: number): string {
	return n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n);
}

export function registerCompactRendering(pi: ExtensionAPI) {
	const cwd = process.cwd();

	// --- bash -----------------------------------------------------------------

	// No powershell delegate: pi only registers it on Windows, and an extension
	// registration is always active — re-registering would add it on macOS.
	const settings = readToolSettings(cwd);
	const originalBash = createBashTool(cwd, {
		shellPath: settings.shellPath,
		commandPrefix: settings.shellCommandPrefix,
	});
	pi.registerTool({
		name: "bash",
		label: "bash",
		description: originalBash.description,
		parameters: originalBash.parameters,
		async execute(toolCallId, params, signal, onUpdate) {
			const t0 = Date.now();
			const result = await originalBash.execute(toolCallId, params, signal, onUpdate);
			const details = (result.details ?? {}) as BashToolDetails & { durationMs?: number };
			return { ...result, details: { ...details, durationMs: Date.now() - t0 } };
		},
		renderCall(args, theme) {
			const command = str(args as Args, "command");
			const timeout = (args as Args).timeout;
			const suffix = timeout ? theme.fg("muted", ` (timeout ${timeout}s)`) : "";
			return linesComponent([theme.fg("toolTitle", theme.bold(`$ `)) + theme.fg("accent", command) + suffix]);
		},
		renderResult(result, { expanded, isPartial }, theme, context) {
			if (isPartial) return linesComponent([theme.fg("warning", "…running")]);
			const details = result.details as (BashToolDetails & { durationMs?: number }) | undefined;
			let { body, exitCode } = splitBashOutput(text(result.content));
			if (context?.isError && exitCode === undefined) exitCode = -1; // failed without a parseable code (e.g. timeout)
			const out = nonEmptyLines(body);
			const took = details?.durationMs ? theme.fg("muted", ` · ${formatDuration(details.durationMs)}`) : "";
			if (out.length === 0) {
				const ec = exitCode && exitCode !== 0 ? theme.fg("error", `exit ${exitCode}`) : theme.fg("success", "✓");
				return linesComponent([ec + took]);
			}
			if (expanded) return linesComponent(out.map((l) => theme.fg("toolOutput", l)));
			// No output preview — a line count plus status is what the eye needs;
			// anything more squares the transcript. ctrl+o shows the real thing.
			const status = exitCode !== undefined && exitCode !== 0 ? theme.fg("error", `exit ${exitCode}`) : theme.fg("success", "✓");
			const n = out.length;
			return linesComponent([
				theme.fg("muted", `… ${formatCount(n)} ${n === 1 ? "line" : "lines"}`) +
					took +
					" " +
					status +
					theme.fg("muted", " (ctrl+o)"),
			]);
		},
	});

	// --- read ---------------------------------------------------------------

	const originalRead = createReadTool(cwd, { autoResizeImages: settings.imageAutoResize });
	pi.registerTool({
		name: "read",
		label: "read",
		description: originalRead.description,
		parameters: originalRead.parameters,
		async execute(toolCallId, params, signal, onUpdate) {
			return originalRead.execute(toolCallId, params, signal, onUpdate);
		},
		renderCall(args, theme) {
			const path = str(args as Args, "path");
			const offset = (args as Args).offset;
			const range = offset ? theme.fg("muted", ` (from line ${offset})`) : "";
			return linesComponent([theme.fg("toolTitle", theme.bold("read ")) + theme.fg("accent", path) + range]);
		},
		renderResult(result, { expanded, isPartial }, theme) {
			if (isPartial) return linesComponent([theme.fg("warning", "…reading")]);
			const content = Array.isArray(result.content) ? result.content : [];
			if (content.some((c) => (c as { type?: string }).type === "image")) {
				return linesComponent([theme.fg("success", "✓ image loaded (ctrl+o to view)")]);
			}
			const out = nonEmptyLines(text(result.content));
			if (out.length === 0) return linesComponent([theme.fg("error", "no content")]);
			if (expanded) return linesComponent(out.map((l) => theme.fg("toolOutput", l)));
			const trunc = (result.details as { truncation?: { truncated?: boolean; totalLines?: number } } | undefined)
				?.truncation;
			const note = trunc?.truncated ? theme.fg("muted", ` (truncated from ${trunc.totalLines})`) : "";
			return linesComponent([theme.fg("success", `✓ ${out.length} lines`) + note]);
		},
	});

	// --- grep ----------------------------------------------------------------

	const originalGrep = createGrepTool(cwd);
	pi.registerTool({
		name: "grep",
		label: "grep",
		description: originalGrep.description,
		parameters: originalGrep.parameters,
		async execute(toolCallId, params, signal, onUpdate) {
			return originalGrep.execute(toolCallId, params, signal, onUpdate);
		},
		renderCall(args, theme) {
			const pattern = str(args as Args, "pattern");
			const path = str(args as Args, "path");
			return linesComponent([
				theme.fg("toolTitle", theme.bold("grep ")) +
					theme.fg("accent", pattern) +
					(path ? theme.fg("muted", ` in ${path}`) : ""),
			]);
		},
		renderResult(result, { expanded, isPartial }, theme) {
			if (isPartial) return linesComponent([theme.fg("warning", "…searching")]);
			const out = nonEmptyLines(text(result.content));
			if (out.length === 0) return linesComponent([theme.fg("success", "no matches")]);
			if (expanded) return linesComponent(out.map((l) => theme.fg("toolOutput", l)));
			const total = (result.details as GrepToolDetails | undefined)?.truncation?.totalLines ?? out.length;
			const preview = out.slice(0, 3).map((l) => theme.fg("toolOutput", l));
			const hidden = Math.max(0, total - preview.length);
			const lines = hidden > 0 ? [...preview, theme.fg("muted", `… ${formatCount(hidden)} more`)] : preview;
			return linesComponent(lines);
		},
	});

	// --- ls / find -----------------------------------------------------------

	for (const name of ["ls", "find"] as const) {
		const original = name === "ls" ? createLsTool(cwd) : createFindTool(cwd);
		pi.registerTool({
			name,
			label: name,
			description: original.description,
			parameters: original.parameters,
			async execute(toolCallId, params, signal, onUpdate) {
				return original.execute(toolCallId, params, signal, onUpdate);
			},
			renderCall(args, theme) {
				const path = str(args as Args, "path") || ".";
				return linesComponent([theme.fg("toolTitle", theme.bold(`${name} `)) + theme.fg("accent", path)]);
			},
			renderResult(result, { expanded, isPartial }, theme) {
				if (isPartial) return linesComponent([theme.fg("warning", `…${name}ing`)]);
				const out = nonEmptyLines(text(result.content));
				if (out.length === 0) return linesComponent([theme.fg("success", `${name}: nothing`)]);
				if (expanded) return linesComponent(out.map((l) => theme.fg("toolOutput", l)));
				const total = (result.details as LsToolDetails | undefined)?.truncation?.totalLines ?? out.length;
				const preview = out.slice(0, 3).map((l) => theme.fg("toolOutput", l));
				const hidden = Math.max(0, total - preview.length);
				const lines = hidden > 0 ? [...preview, theme.fg("muted", `… ${formatCount(hidden)} more`)] : preview;
				return linesComponent(lines);
			},
		});
	}

	// --- write ----------------------------------------------------------------

	const originalWrite = createWriteTool(cwd);
	pi.registerTool({
		name: "write",
		label: "write",
		description: originalWrite.description,
		parameters: originalWrite.parameters,
		async execute(toolCallId, params, signal, onUpdate) {
			return originalWrite.execute(toolCallId, params, signal, onUpdate);
		},
		renderCall(args, theme) {
			const path = str(args as Args, "path");
			const contentLines = str(args as Args, "content").split("\n").length;
			return linesComponent([
				theme.fg("toolTitle", theme.bold("write ")) +
					theme.fg("accent", path) +
					theme.fg("muted", ` (${contentLines} lines)`),
			]);
		},
		renderResult(result, { isPartial }, theme) {
			if (isPartial) return linesComponent([theme.fg("warning", "…writing")]);
			const out = text(result.content);
			if (out.startsWith("Error")) return linesComponent([theme.fg("error", out.split("\n")[0])]);
			return linesComponent([theme.fg("success", "✓ written")]);
		},
	});

	// Diffs are the review surface, so collapsed edit results keep the stat line
	// and only the diff itself is expanded away.

	const originalEdit = createEditTool(cwd);
	pi.registerTool({
		name: "edit",
		label: "edit",
		description: originalEdit.description,
		parameters: originalEdit.parameters,
		async execute(toolCallId, params, signal, onUpdate) {
			return originalEdit.execute(toolCallId, params, signal, onUpdate);
		},
		renderCall(args, theme) {
			return linesComponent([theme.fg("toolTitle", theme.bold("edit ")) + theme.fg("accent", str(args as Args, "path"))]);
		},
		renderResult(result, { expanded, isPartial }, theme) {
			if (isPartial) return linesComponent([theme.fg("warning", "…editing")]);
			const details = result.details as EditToolDetails | undefined;
			const out = text(result.content);
			if (out.startsWith("Error")) return linesComponent([theme.fg("error", out.split("\n")[0])]);
			const diff = details?.diff ?? "";
			const diffLines = diff.split("\n").filter((l) => l.trim() !== "");
			let additions = 0;
			let removals = 0;
			for (const line of diffLines) {
				if (line.startsWith("+") && !line.startsWith("+++")) additions++;
				if (line.startsWith("-") && !line.startsWith("---")) removals++;
			}
			const stat = `${theme.fg("success", `+${additions}`)} ${theme.fg("error", `-${removals}`)}`;
			if (expanded) {
				return linesComponent([
					stat,
					...diffLines.map((l) =>
						l.startsWith("+") && !l.startsWith("+++")
							? theme.fg("success", l)
							: l.startsWith("-") && !l.startsWith("---")
								? theme.fg("error", l)
								: theme.fg("dim", l),
					),
				]);
			}
			return linesComponent([stat]);
		},
	});
}

function formatDuration(ms: number): string {
	return ms >= 1000 ? `${(ms / 1000).toFixed(1)}s` : `${ms}ms`;
}
