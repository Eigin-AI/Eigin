/**
 * Unit tests for the hard-invariant bash guards.
 */

import { checkCommand, stripHeredocBodies } from "./guards.ts";

function test(name: string, fn: () => void): void {
	try {
		fn();
		console.log(`✓ ${name}`);
	} catch (err) {
		console.error(`✗ ${name}`);
		console.error(err);
		process.exitCode = 1;
	}
}

function assertBlocked(command: string, message?: string): void {
	const result = checkCommand(command);
	if (!result) {
		throw new Error(`${message || "Expected block"}\nCommand: ${command}`);
	}
}

function assertAllowed(command: string, message?: string): void {
	const result = checkCommand(command);
	if (result) {
		throw new Error(`${message || "Expected allow"}\nCommand: ${command}\nReason: ${result.reason}`);
	}
}

// --- Real invocations still blocked -------------------------------------

test("blocks git commit", () => {
	assertBlocked("git commit -m 'wip'");
});

test("blocks git push", () => {
	assertBlocked("git push origin main");
});

test("blocks git merge", () => {
	assertBlocked("git merge feature/foo");
});

test("blocks git rebase", () => {
	assertBlocked("git rebase main");
});

test("blocks git reset", () => {
	assertBlocked("git reset --hard HEAD~1");
});

test("blocks git branch delete", () => {
	assertBlocked("git branch -D old-branch");
});

test("blocks git remote mutation", () => {
	assertBlocked("git remote add origin git@example.com:foo/bar.git");
});

test("blocks terraform apply", () => {
	assertBlocked("terraform apply");
});

test("blocks terraform destroy", () => {
	assertBlocked("terraform destroy -auto-approve");
});

test("blocks tofu apply (OpenTofu equivalent)", () => {
	assertBlocked("tofu apply");
});

test("blocks terraform apply chained after another command", () => {
	assertBlocked("cd infra && terraform apply");
});

test("blocks just infra deploy with no env arg", () => {
	assertBlocked("just infra deploy");
});

test("blocks just infra deploy staging", () => {
	assertBlocked("just infra deploy staging");
});

test("blocks just infra deploy production", () => {
	assertBlocked("just infra deploy production");
});

test("blocks just infra deploy chained after another command", () => {
	assertBlocked("cd /repo && just infra deploy staging");
});

test("allows just infra plan", () => {
	assertAllowed("just infra plan staging");
});

test("allows just infra init", () => {
	assertAllowed("just infra init staging");
});

// --- Real invocations inside heredoc-adjacent commands still blocked ----

test("blocks git commit that also happens to write a heredoc first", () => {
	assertBlocked("cat > note.txt << 'EOF'\nsome text\nEOF\ngit commit -am 'wip'");
});

// --- False positives: prose inside heredoc bodies is not a real command -

test("allows documentation mentioning 'terraform apply' inside a heredoc", () => {
	assertAllowed("cat > doc.md << 'EOF'\nBlocked: `terraform apply`/`destroy` is the user's to run.\nEOF");
});

test("allows documentation mentioning 'git commit' inside a heredoc", () => {
	assertAllowed("cat > doc.md << 'EOF'\nCommit, push, and merge are the user's to run.\nEOF");
});

test("allows a heredoc body containing the literal command as an example", () => {
	assertAllowed("cat > doc.md << 'EOF'\nRun `terraform apply` to deploy.\nEOF");
});

test("allows documentation mentioning 'just infra deploy' inside a heredoc", () => {
	assertAllowed("cat > doc.md << 'EOF'\nUse `just infra deploy production` to ship.\nEOF");
});

test("allows multiple heredocs where only the body mentions blocked terms", () => {
	assertAllowed(
		"cat > a.md << 'A'\ngit commit example\nA\ncat > b.md << 'B'\nterraform destroy example\nB",
	);
});

// --- Read-only / safe commands stay allowed -----------------------------

test("allows git status", () => {
	assertAllowed("git status");
});

test("allows git log", () => {
	assertAllowed("git log --oneline -10");
});

test("allows git diff", () => {
	assertAllowed("git diff HEAD~1");
});

test("allows terraform plan", () => {
	assertAllowed("terraform plan");
});

test("allows unrelated commands", () => {
	assertAllowed("ls -la && cat package.json");
});

// --- stripHeredocBodies unit behavior ------------------------------------

test("stripHeredocBodies removes body but keeps opener and surrounding text", () => {
	const input = "echo before\ncat > f << 'EOF'\nsecret body line\nEOF\necho after";
	const result = stripHeredocBodies(input);
	if (result.includes("secret body line")) {
		throw new Error(`Body should have been stripped.\nGot: ${result}`);
	}
	if (!result.includes("echo before") || !result.includes("echo after")) {
		throw new Error(`Surrounding text should be preserved.\nGot: ${result}`);
	}
});

test("stripHeredocBodies handles quoted and unquoted delimiters", () => {
	const quoted = stripHeredocBodies("cat << 'END'\nterraform apply\nEND");
	const unquoted = stripHeredocBodies("cat << END\nterraform apply\nEND");
	if (quoted.includes("terraform apply") || unquoted.includes("terraform apply")) {
		throw new Error("Both quoted and unquoted heredoc delimiters should strip the body");
	}
});

console.log("\nAll guard tests completed.");
