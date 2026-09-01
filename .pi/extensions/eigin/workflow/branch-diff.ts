/**
 * The branch's changes against main, written to a file for a reviewer to read.
 *
 * A diff big enough to be worth reviewing is too big to pass through a prompt,
 * so it goes to `.pi/review/<branch>.diff` and the reviewer is given the path.
 */

import { execFile } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);

/** Git-ignored scratch dir, mirroring `.pi/mr/`. */
export const REVIEW_DIR = ".pi/review";

type Git = (args: string[]) => Promise<{ stdout: string }>;

/**
 * New files a branch adds are untracked, so `git diff` can't see them.
 * Diffs each against /dev/null rather than `git add -N`, which would leave
 * the user's index changed behind their back.
 */
async function untrackedDiff(git: Git): Promise<string> {
	const { stdout } = await git(["ls-files", "--others", "--exclude-standard"]);
	const files = stdout.split("\n").filter(Boolean);

	const diffs = await Promise.all(
		files.map(async (file) => {
			// --no-index exits 1 when the files differ, which is every time here.
			const { stdout: d } = await git(["diff", "--no-index", "--", "/dev/null", file]).catch(
				(err: { stdout?: string }) => ({ stdout: err.stdout ?? "" }),
			);
			return d;
		}),
	);
	return diffs.join("");
}

/**
 * Writes the branch's full diff against main — committed, uncommitted, and
 * untracked — to `.pi/review/<branch>.diff`. Returns null when there's
 * nothing to review or git can't answer (no remote, detached head).
 *
 * Diffs from the merge base so commits that landed on main since the branch
 * started don't show up as this branch's work.
 */
export async function writeBranchDiff(cwd: string): Promise<string | null> {
	const git: Git = (args) => run("git", args, { cwd, maxBuffer: 64 * 1024 * 1024 });

	let branch: string;
	let base: string;
	try {
		branch = (await git(["branch", "--show-current"])).stdout.trim();
		// origin/main is the shared truth; fall back to a local main-only clone.
		const ref = await git(["rev-parse", "--verify", "--quiet", "origin/main"])
			.then(() => "origin/main")
			.catch(() => "main");
		base = (await git(["merge-base", ref, "HEAD"])).stdout.trim();
	} catch {
		return null;
	}
	if (!branch || !base) return null;

	const tracked = (await git(["diff", base])).stdout;
	const diff = `${tracked}${await untrackedDiff(git)}`;
	if (!diff.trim()) return null;

	const file = resolve(cwd, REVIEW_DIR, `${branch.replace(/\//g, "-")}.diff`);
	await mkdir(resolve(cwd, REVIEW_DIR), { recursive: true });
	await writeFile(file, diff, "utf-8");
	return file;
}
