/**
 * Unit tests for guidance loading. The important one is coverage: every stage
 * of every workflow must resolve to a real file, so a rename or a deleted
 * `.pi/guidance/*.md` fails here instead of silently leaving a stage unguided.
 */

import { mkdtempSync, mkdirSync, writeFileSync, utimesSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { findGuidanceDir, loadGuidance, loadGuidanceFile } from "./guidance.ts";
import { WORKFLOWS } from "./workflows.ts";

const REPO = path.resolve(import.meta.dirname, "../../../..");

function test(name: string, fn: () => void | Promise<void>): void {
	Promise.resolve(fn()).then(
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

test("every workflow stage resolves to a guidance file", async () => {
	for (const workflow of WORKFLOWS) {
		for (const stage of workflow.stages) {
			const text = await loadGuidance(REPO, workflow.id, stage.id);
			assert(
				!text.startsWith("No guidance file"),
				`${workflow.id}/${stage.id}: no guidance file found — ${text}`,
			);
			assert(text.length > 0, `${workflow.id}/${stage.id}: empty guidance`);
		}
	}
});

test("guidance is tuned per workflow", async () => {
	const bug = await loadGuidance(REPO, "bug", "context");
	const feature = await loadGuidance(REPO, "feature", "context");
	assert(bug.includes("reproduce"), "bug context guidance should mention reproduction");
	assert(bug !== feature, "bug and feature context guidance should differ");
});

test("merge guidance is shared by feature, bug and prototype", async () => {
	const feature = await loadGuidance(REPO, "feature", "merge");
	const bug = await loadGuidance(REPO, "bug", "merge");
	const prototype = await loadGuidance(REPO, "prototype", "merge");
	const release = await loadGuidance(REPO, "release", "merge");
	assert(feature === bug && bug === prototype, "shared merge guidance should be identical");
	assert(release !== feature, "release should override the shared merge guidance");
});

test("git-policy loads as a standalone file", async () => {
	const policy = await loadGuidanceFile(REPO, "git-policy");
	assert(policy !== null && policy.includes("force-push"), "expected the git policy text");
	assert((await loadGuidanceFile(REPO, "no-such-file")) === null, "missing file should be null");
});

test("a missing stage file reports the paths it tried", async () => {
	const dir = mkdtempSync(path.join(tmpdir(), "guidance-"));
	mkdirSync(path.join(dir, ".pi/guidance"), { recursive: true });
	const text = await loadGuidance(dir, "feature", "build");
	assert(text.startsWith("No guidance file"), "expected the missing-file message");
	assert(text.includes("feature/build.md"), "message should name the path it tried");
});

test("an edited file is re-read on the next load", async () => {
	const dir = mkdtempSync(path.join(tmpdir(), "guidance-"));
	mkdirSync(path.join(dir, ".pi/guidance"), { recursive: true });
	const file = path.join(dir, ".pi/guidance/build.md");

	writeFileSync(file, "first");
	assert((await loadGuidance(dir, "feature", "build")) === "first", "expected the original text");

	writeFileSync(file, "second");
	const future = new Date(Date.now() + 1000);
	utimesSync(file, future, future); // Same-millisecond writes would look unchanged.
	assert((await loadGuidance(dir, "feature", "build")) === "second", "expected the edited text");
});

test("findGuidanceDir walks up from a nested cwd", () => {
	const nested = path.join(REPO, ".pi/extensions/eigin/workflow");
	assert(findGuidanceDir(nested) === path.join(REPO, ".pi/guidance"), "should find the repo's guidance dir");
	assert(findGuidanceDir(tmpdir()) === null, "should return null when there is none above cwd");
});
