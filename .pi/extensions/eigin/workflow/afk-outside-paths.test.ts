/**
 * Unit tests for the AFK outside-path scan.
 */

import { homedir } from "node:os";
import { bashPathCandidates, firstOutsidePath, isWithinBoundary, pathIsOutside } from "./afk-outside-paths.ts";

function test(name: string, fn: () => void): void {
	try {
		fn();
		console.log(`✓ ${name}`);
	} catch (err) {
		console.error(`✗ ${name}`);
		console.error((err as Error).stack);
		process.exitCode = 1;
	}
}

function assert(condition: boolean, message: string): void {
	if (!condition) throw new Error(message);
}

const home = homedir(); // expandHome resolves ~ to the real home; tests must agree
const cwd = `${home}/Repositories/eigin`;
// Factitious roots matching the shipped config, for a hermetic test env.
const allowed = {
	roots: ["/tmp", "/private/tmp", "/var/folders", `${home}/Repositories`, `${home}/Library/Caches`],
	mode: "ask" as const,
};

test("in-workspace and granted paths pass", () => {
	assert(firstOutsidePath("ls src && cat /tmp/x", cwd, allowed) === null, "workspace + /tmp should pass");
	assert(
		firstOutsidePath("ls ~/Library/Caches/org.swift.swiftpm", cwd, allowed) === null,
		"the caches grant should pass",
	);
});

test("outside paths are flagged with a ~-collapsed display", () => {
	const hit = firstOutsidePath("ls ~/Music", cwd, allowed);
	assert(hit !== null && hit.display === "~/Music", `should flag ~/Music (got ${hit?.display})`);
	const abs = firstOutsidePath("cat /etc/hosts", cwd, allowed);
	assert(abs !== null && abs.display === "/etc/hosts", "absolute paths collapse by home, not to nothing");
});

test("non-path tokens and /dev devices never flag", () => {
	assert(
		firstOutsidePath(
			"git clone git@github.com:owner/repo.git -o /dev/null | grep https://x.com/a/b",
			cwd,
			allowed,
		) === null,
		"remotes, URLs and /dev/null are not paths",
	);
	assert(firstOutsidePath("echo $HOME/etc/passwd", cwd, allowed) === null, "shell expansions shouldn't flag");
	assert(firstOutsidePath("git status 2>/dev/null", cwd, allowed) === null, "granted devices are not paths");
	assert(
		firstOutsidePath("echo boom 2>/dev/console", cwd, allowed) !== null,
		"ungranted devices still flag — AFK denies, guardrails doesn't hang",
	);
});

test("redirect targets flag like any other path", () => {
	assert(firstOutsidePath("git diff > /Users/x/Desktop/d.txt", cwd, allowed) !== null, "redirects out should flag");
	assert(firstOutsidePath("echo hi >/etc/hosts", cwd, allowed) !== null, "glued redirects should flag");
});

test("cd elsewhere doesn't launder relative paths in, but its argument still flags", () => {
	assert(firstOutsidePath("cd ~/Desktop && ls", cwd, allowed) !== null, "the cd argument should flag");
});

test("allow mode never flags", () => {
	assert(firstOutsidePath("cat /etc/hosts", cwd, { roots: allowed.roots, mode: "allow" }) === null, "allow disables the gate");
});

test("boundary check: equal, inside, outside", () => {
	assert(isWithinBoundary(cwd, cwd), "equal");
	assert(isWithinBoundary(`${cwd}/src/a.ts`, cwd), "descendant");
	assert(!isWithinBoundary("/tmp/xy", cwd), "sibling");
	assert(!isWithinBoundary("/Users/x/RepositoriesX/y", `${home}/Repositories`), "prefix needs a separator");
});

test("write/edit check mirrors the command check", () => {
	assert(pathIsOutside(`${cwd}/src/a.ts`, cwd, allowed) === null, "inside passes");
	assert(pathIsOutside(`${home}/Library/Caches/x`, cwd, allowed) === null, "grant passes");
	const hit = pathIsOutside(`${home}/Documents/x`, cwd, allowed);
	assert(hit !== null && hit.display === "~/Documents/x", `outside flags (got ${hit?.display})`);
});

test("candidates: only path-shaped tokens survive", () => {
	const c = bashPathCandidates("xcrun simctl list; cargo build --release 2>/dev/null");
	assert(!c.some((t) => t.includes("2>/")), "redirect decoration shouldn't reach candidates");
});
