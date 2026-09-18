# Merge stage

Open the GitLab MR, and drive review to a merge.

The merge action itself is always manual, performed by the user.

Signpost briefly what you expect the user to do — keep the flow tight and self-evident.

## Open the MR

1. Confirm the branch is pushed.
2. Draft the MR description — follow `.gitlab/merge_request_templates/Default.md`, matched to the length and tone of this example `.pi/guidance/mr-example.md`.
    - Keep it short and concise.
    - Focus on what changed and why it matters;
      leave how it works to the code.
    - No design history, no decision log.
    - Avoid referencing gitignored artifacts such as in `.pi/plans/` and `.pi/mr/`.
3. Save to `.pi/mr/<issue#>-<work-name>.md` (e.g. `162-auto-activating-skills.md`; drop the issue# if none).
4. Create the MR (project: dev/eigin on code.eigin.ai):
   `glab mr create --title "..." --description "$(cat <path>)" --source-branch <branch>`
    - Title in Conventional Commits form: pick the type from what the MR actually does
      (`feat`, `fix`, `refactor`, `chore`, `docs`, `test`, …), then a short, lowercase,
      imperative summary.
    - Good: `feat: disclose tool payloads in permission prompts`.
    - Check `glab label list` for the right tags.
5. Open it for the user: `glab mr view --web` (on the current branch).

## Review loop

Repeat until the user merges:

1. wait_for_user (prompt "Review the MR and leave comments"; confirmLabel "Pull my comments").
2. Pull unresolved comments — PAGINATE so none are missed:
   `glab api projects/:id/merge_requests/:iid/discussions --paginate`
   (get the iid via `glab mr view --output json` on the current branch).
   Turn actionable comments into tasks (add_tasks) so they stay in context.
3. Fix what's directly fixable and resolve those threads (the user can reopen).
4. Answer questions in-thread via
   `glab api ...merge_requests/:iid/discussions/:id/notes`, prefixing replies with "**Agent**:".
5. Summarize anything left in chat. Resolve each task as its thread is handled.
