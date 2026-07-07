/**
 * Hard invariants — always enforced, in every stage, with no override.
 *
 * These encode actions the agent must never take:
 *  - stateful/destructive git (the user drives git and merges themselves)
 *  - `terraform apply` / `terraform destroy` (and OpenTofu equivalents)
 *  - `just infra deploy` (the justfile recipe that wraps `terraform apply`)
 *
 * Read-only git (status/log/diff/show/...) and `terraform plan` stay allowed.
 * Extend the lists below as new never-do actions come up.
 *
 * Matching is substring-based, not a real shell parser, so heredoc bodies
 * (`<<'EOF' ... EOF`) are stripped before scanning — that's data being written
 * to a file/stdin, not a command being executed. Without this, writing
 * documentation or a plan that merely *mentions* "terraform apply" or "git
 * commit" in prose would trip the guard.
 */

// Mutating/stateful git subcommands the agent must never run.
const GIT_WRITE_SUBCOMMANDS = ["commit", "push", "merge", "rebase", "reset"];

const GIT_WRITE = new RegExp(
  `\\bgit\\s+(?:-\\S+\\s+)*(?:${GIT_WRITE_SUBCOMMANDS.join("|")})\\b`,
  "i",
);

// Creating/deleting/renaming branches or moving refs, e.g. `git branch -D foo`.
const GIT_BRANCH_MUTATE = /\bgit\s+branch\s+(?:\S+\s+)*-(?:d|D|m|M|f)\b/i;

// Mutating remotes, e.g. `git remote add|remove|rename|set-url`.
const GIT_REMOTE_MUTATE =
  /\bgit\s+remote\s+(?:add|remove|rm|rename|set-url|set-head|prune)\b/i;

// `terraform apply|destroy` and OpenTofu (`tofu`) equivalents.
const TERRAFORM_APPLY = /\b(?:terraform|tofu)\s+(?:apply|destroy)\b/i;

// `just infra deploy [env]` — the justfile recipe that runs `terraform apply`
// under the hood (see the `infra` recipe). The literal words "terraform
// apply" never appear in this invocation, so TERRAFORM_APPLY above wouldn't
// catch it; it needs its own check.
const JUST_INFRA_DEPLOY = /\bjust\s+(?:-\S+\s+)*infra\s+deploy\b/i;

export interface GuardViolation {
  reason: string;
}

/**
 * Remove heredoc bodies (`<<'EOF' ... EOF`, `<<-EOF ... EOF`, etc.) from a
 * bash command string before scanning for guard violations. Heredoc content
 * is data being written to a file or piped to stdin — not a command being
 * executed — so keyword matches inside it are not real invocations.
 */
export function stripHeredocBodies(command: string): string {
  const HEREDOC_OPENER = /<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/g;
  let result = "";
  let cursor = 0;
  let match: RegExpExecArray | null;

  while ((match = HEREDOC_OPENER.exec(command)) !== null) {
    const delimiter = match[2];
    const openerEnd = match.index + match[0].length;

    const lineEnd = command.indexOf("\n", openerEnd);
    if (lineEnd === -1) break; // No newline after the opener; nothing to strip.

    const rest = command.slice(lineEnd + 1);
    const closerRe = new RegExp(`^[ \\t]*${delimiter}[ \\t]*$`, "m");
    const closerMatch = closerRe.exec(rest);

    result += command.slice(cursor, lineEnd + 1);

    if (!closerMatch) {
      // Unterminated heredoc (unusual) — treat the remainder as body and stop.
      cursor = command.length;
      break;
    }

    cursor = lineEnd + 1 + closerMatch.index + closerMatch[0].length;
    HEREDOC_OPENER.lastIndex = cursor;
  }

  result += command.slice(cursor);
  return result;
}

/**
 * Inspect a bash command for hard-invariant violations.
 * Returns a violation to block on, or null if the command is allowed.
 */
export function checkCommand(command: string): GuardViolation | null {
  const scoped = stripHeredocBodies(command);

  if (
    GIT_WRITE.test(scoped) ||
    GIT_BRANCH_MUTATE.test(scoped) ||
    GIT_REMOTE_MUTATE.test(scoped)
  ) {
    return {
      reason:
        "Blocked: the agent should not run stateful or destructive git operations. " +
        "This is something the user should do — discuss it with them, or tell them what to run. " +
        "Commit, push, branch changes, and merges are theirs; read-only git (status/log/diff/show) is fine.",
    };
  }
  if (TERRAFORM_APPLY.test(scoped)) {
    return {
      reason:
        "Blocked: the agent should not run `terraform apply`/`destroy`. " +
        "This is the user's to run — discuss it with them or tell them what to try. `terraform plan` is fine.",
    };
  }
  if (JUST_INFRA_DEPLOY.test(scoped)) {
    return {
      reason:
        "Blocked: the agent should not run `just infra deploy` — it wraps `terraform apply` and deploys infra. " +
        "This is the user's to run — discuss it with them or tell them what to try. `just infra plan`/`init` are fine.",
    };
  }
  return null;
}
