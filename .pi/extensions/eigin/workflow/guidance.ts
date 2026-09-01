/**
 * Stage guidance, stored as markdown under `.pi/guidance/` instead of inline
 * in code, so it can be edited without touching the extension.
 *
 * Files are re-read when they change, so an edit takes effect on the next
 * turn — no restart.
 *
 * Lookup order for a stage:
 *   1. `.pi/guidance/<workflow>/<stage>.md` — tuned to that workflow
 *   2. `.pi/guidance/<stage>.md` — shared across workflows (merge)
 */

import { readFile, stat } from "node:fs/promises";
import { statSync } from "node:fs";
import * as path from "node:path";
import type { StageId } from "./stages.ts";
import type { WorkflowId } from "./workflows.ts";

const GUIDANCE_DIR = ".pi/guidance";

interface CacheEntry {
	mtimeMs: number;
	text: string;
}

const cache = new Map<string, CacheEntry>();

function isDirectory(p: string): boolean {
	try {
		return statSync(p).isDirectory();
	} catch {
		return false;
	}
}

/** Nearest `.pi/guidance` at or above `cwd`, so worktrees resolve their own. */
export function findGuidanceDir(cwd: string): string | null {
	let dir = cwd;
	while (true) {
		const candidate = path.join(dir, GUIDANCE_DIR);
		if (isDirectory(candidate)) return candidate;
		const parent = path.dirname(dir);
		if (parent === dir) return null;
		dir = parent;
	}
}

/** Read a guidance file, re-reading only when its mtime has moved. */
async function readCached(file: string): Promise<string | null> {
	let mtimeMs: number;
	try {
		mtimeMs = (await stat(file)).mtimeMs;
	} catch {
		return null;
	}

	const hit = cache.get(file);
	if (hit && hit.mtimeMs === mtimeMs) return hit.text;

	try {
		const text = (await readFile(file, "utf-8")).trim();
		cache.set(file, { mtimeMs, text });
		return text;
	} catch {
		return null;
	}
}

/**
 * Guidance for a stage within a workflow. Never throws: a missing file
 * returns a message naming the paths that were tried, so the gap shows up in
 * the agent's stage hint instead of silently leaving it unguided.
 */
export async function loadGuidance(cwd: string, workflow: WorkflowId, stage: StageId): Promise<string> {
	const dir = findGuidanceDir(cwd);
	const candidates = dir ? [path.join(dir, workflow, `${stage}.md`), path.join(dir, `${stage}.md`)] : [];

	for (const file of candidates) {
		const text = await readCached(file);
		if (text) return text;
	}

	const tried = candidates.length > 0 ? candidates.join(" or ") : `${GUIDANCE_DIR}/ (not found above ${cwd})`;
	return `No guidance file for the ${workflow}/${stage} stage — expected ${tried}. Tell the user; work from the conversation meanwhile.`;
}

/** A standalone guidance file, e.g. `git-policy` for the system prompt. */
export async function loadGuidanceFile(cwd: string, name: string): Promise<string | null> {
	const dir = findGuidanceDir(cwd);
	if (!dir) return null;
	return readCached(path.join(dir, `${name}.md`));
}
