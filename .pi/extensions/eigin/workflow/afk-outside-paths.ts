/**
 * AFK pre-empt for guardrails' path gate — the self-contained variant.
 *
 * The gate prompts whenever a tool touches a path outside the workspace and a
 * UI exists — which AFK still has, so the dialog hangs. Guardrails' own
 * no-UI fallback is a hard deny, so we reproduce that decision here, in our
 * `tool_call` handler (which runs before guardrails registers its prompt):
 * block anything outside the workspace before the dialog can open.
 *
 * Why not flip guardrails' live config mode instead: the loader instance we
 * can import is not guaranteed to be the one guardrails' extensions use (pi
 * may load the package's compiled modules under a separate identity), so the
 * mutation can land on a copy — silently. That was observed live. This module
 * needs no guardrails imports: it parses the same `guardrails.json` the
 * extension reads and applies the same boundary rule, leaning strict (a
 * missed grant or an over-eager candidate is a denial the agent routes
 * around, never a hang).
 *
 * Bash paths are extracted by token shape, not by re-implementing guardrails'
 * classifier: every absolute or `~`-rooted token is a candidate, minus the
 * shapes that cannot be paths (URLs, remotes, shell expansions) plus the
 * /dev character devices pipelines habitually redirect to. Relative tokens
 * resolve into the workspace, which is inside the boundary by definition.
 */

import { homedir } from "node:os";
import { isAbsolute, relative, resolve } from "node:path";
import { readFile } from "node:fs/promises";

/** The slice of guardrails.json this module reads. */
export interface PathAccessFile {
	pathAccess?: {
		mode?: string;
		allowedPaths?: Array<{ kind?: string; path?: string }>;
	};
}

/** Node-style boundary check: target equals root or is a descendant. */
export function isWithinBoundary(targetAbsPath: string, rootAbsPath: string): boolean {
	const rel = relative(rootAbsPath, targetAbsPath);
	return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
}

/** Expand a leading `~` to the user's home directory. */
export function expandHome(input: string): string {
	if (input === "~") return homedir();
	if (input.startsWith("~/")) return resolve(homedir(), input.slice(2));
	return input;
}

/** Character devices every shell pipeline redirects through. Grants for these
 * live in guardrails.json as file entries — this set matches them exactly, so
 * AFK never blocks a redirect guardrails itself allows, and never skips one it
 * would prompt on. */
const DEV_NULLS = new Set([
	"/dev/null",
	"/dev/zero",
	"/dev/urandom",
	"/dev/random",
	"/dev/stdin",
	"/dev/stdout",
	"/dev/stderr",
	"/dev/tty",
]);

function isCharacterDevice(token: string): boolean {
	return DEV_NULLS.has(token);
}

/** Shapes that cannot be local paths — mirrors guardrails' appearance filters. */
const NON_PATH = [/^[a-z][a-z0-9+.-]*:\/\//i, /^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+:/, /\$[A-Za-z_{(]|`/];

/** Extract path-shaped tokens from a bash command line. */
export function bashPathCandidates(command: string): string[] {
	const candidates: string[] = [];
	for (const token of command.split(/[\s"';|&()<>]+/)) {
		if (!token) continue;
		if (NON_PATH.some((re) => re.test(token))) continue;
		if (token.startsWith("/")) {
			if (!isCharacterDevice(token)) candidates.push(token);
		} else if (token.startsWith("~")) {
			candidates.push(token);
		}
	}
	return candidates;
}

export interface AllowedRoots {
	/** Absolute directories (already home-expanded) the config grants. */
	roots: string[];
	/** The configured mode, for mirroring guardrails' semantics. */
	mode: "allow" | "ask" | "block";
}

const BUILTIN_ROOTS = ["/tmp", "/private/tmp", "/var/folders"];

/** Read the workspace grants: the project's guardrails.json merged with the builtin roots. */
export async function loadAllowedRoots(configPath: string): Promise<AllowedRoots> {
	const roots = [...BUILTIN_ROOTS];
	let mode: AllowedRoots["mode"] = "ask";
	try {
		const raw = await readFile(configPath, "utf8");
		const config = JSON.parse(raw) as PathAccessFile;
		const pathAccess = config.pathAccess;
		if (pathAccess?.mode === "allow" || pathAccess?.mode === "ask" || pathAccess?.mode === "block") {
			mode = pathAccess.mode;
		}
		for (const entry of pathAccess?.allowedPaths ?? []) {
			if (kindOf(entry) !== "directory") continue;
			if (typeof entry.path !== "string" || !entry.path) continue;
			roots.push(expandHome(entry.path));
		}
	} catch {
		// No/broken config: fall back to builtin roots and the `ask` default.
	}
	return { roots: roots.map((r) => resolve(r)), mode };
}

function kindOf(entry: { kind?: string }): string {
	return entry.kind ?? (typeof entry.path === "string" && entry.path.endsWith("/") ? "directory" : "file");
}

/**
 * The first path-like thing in the command that guardrails would prompt on,
 * or null if everything is inside the workspace or an allowed root.
 * Mode `allow` never flags; `block` and `ask` both flag (AFK converts both to
 * a denial — it can't confirm either).
 */
export function firstOutsidePath(
	command: string,
	cwd: string,
	allowed: AllowedRoots,
): { path: string; display: string } | null {
	if (allowed.mode === "allow") return null;
	for (const token of bashPathCandidates(command)) {
		const abs = isAbsolute(token) ? token : expandHome(token);
		if (isWithinBoundary(abs, cwd)) continue;
		if (allowed.roots.some((root) => isWithinBoundary(abs, root))) continue;
		const home = homedir();
		const display = isWithinBoundary(abs, home) ? `~${abs.slice(home.length)}` : abs;
		return { path: abs, display };
	}
	return null;
}

/** The write/edit-check counterpart: a single path argument instead of a command line. */
export function pathIsOutside(path: string, cwd: string, allowed: AllowedRoots): { path: string; display: string } | null {
	if (allowed.mode === "allow") return null;
	const abs = isAbsolute(path) ? path : expandHome(path);
	if (isWithinBoundary(abs, cwd)) return null;
	if (allowed.roots.some((root) => isWithinBoundary(abs, root))) return null;
	const home = homedir();
	const display = isWithinBoundary(abs, home) ? `~${abs.slice(home.length)}` : abs;
	return { path: abs, display };
}
