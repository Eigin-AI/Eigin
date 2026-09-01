/**
 * Tests for the branch diff, run against real git in a temp repo — the value
 * here is what git actually reports, so faking it would test nothing.
 */

import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { writeBranchDiff } from "./branch-diff.ts";

function test(name: string, fn: () => Promise<void>): void {
	fn().then(
		() => console.log(`✓ ${name}`),
		(err) => {
			console.error(`✗ ${name}`);
			console.error(err);
			process.exitCode = 1;
		},
	);
}

function assert(condition: boolean, message: string): void {
	if (!condition) throw new Error(message);
}

/** A repo with one commit on main, then a branch with changes of every kind. */
function repoWithBranch(): string {
	const dir = mkdtempSync(path.join(tmpdir(), "branch-diff-"));
	const git = (...args: string[]) => execFileSync("git", args, { cwd: dir, stdio: "pipe" });

	git("init", "-b", "main");
	git("config", "user.email", "test@example.com");
	git("config", "user.name", "Test");
	writeFileSync(path.join(dir, "kept.txt"), "original\n");
	writeFileSync(path.join(dir, ".gitignore"), "ignored.txt\n.pi/review/\n");
	git("add", "-A");
	git("commit", "-m", "base");

	git("checkout", "-b", "feature/thing");
	writeFileSync(path.join(dir, "committed.txt"), "committed on the branch\n");
	git("add", "committed.txt");
	git("commit", "-m", "add committed");
	writeFileSync(path.join(dir, "kept.txt"), "modified\n");
	writeFileSync(path.join(dir, "untracked.txt"), "brand new file\n");
	writeFileSync(path.join(dir, "ignored.txt"), "should not be reviewed\n");
	return dir;
}

test("diff covers committed, uncommitted and untracked changes", async () => {
	const dir = repoWithBranch();
	const file = await writeBranchDiff(dir);
	assert(file !== null, "expected a diff file");
	const diff = readFileSync(file as string, "utf-8");

	assert(diff.includes("committed.txt"), "should include a file committed on the branch");
	assert(diff.includes("modified"), "should include uncommitted edits to tracked files");
	assert(diff.includes("brand new file"), "should include untracked files");
	assert(!diff.includes("should not be reviewed"), "should respect .gitignore");
});

test("diff is written to .pi/review, named for the branch", async () => {
	const dir = repoWithBranch();
	const file = await writeBranchDiff(dir);
	// Slashes in the branch name would otherwise read as directories.
	assert(file?.endsWith(".pi/review/feature-thing.diff") === true, `unexpected path: ${file}`);
});

test("a branch with no changes yields nothing to review", async () => {
	const dir = mkdtempSync(path.join(tmpdir(), "branch-diff-"));
	const git = (...args: string[]) => execFileSync("git", args, { cwd: dir, stdio: "pipe" });
	git("init", "-b", "main");
	git("config", "user.email", "test@example.com");
	git("config", "user.name", "Test");
	writeFileSync(path.join(dir, "kept.txt"), "original\n");
	git("add", "-A");
	git("commit", "-m", "base");

	assert((await writeBranchDiff(dir)) === null, "expected null when nothing changed");
});

test("a directory that isn't a repo yields nothing to review", async () => {
	const dir = mkdtempSync(path.join(tmpdir(), "not-a-repo-"));
	mkdirSync(path.join(dir, "src"));
	assert((await writeBranchDiff(dir)) === null, "expected null outside a git repo");
});
