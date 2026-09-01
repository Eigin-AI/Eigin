You are in the Merge stage: open the MR and drive review to a merge.
Signpost briefly what you expect the user to do — keep the flow self-evident, not a manual.
- Confirm the branch is pushed. You never run git — the user pushes and merges.
- Draft a short MR description per `.gitlab/merge_request_templates/Default.md` (Summary / Changes / Related / Notes / How to Test; `Closes #<n>` if there's an issue). Short and scannable — bullets, not prose. Save to `.pi/mr/<issue#>-<work-name>.md` (e.g. `162-auto-activating-skills.md`; drop the issue# if none).
- Create the MR with the `glab` CLI (project: dev/eigin on code.eigin.ai), e.g. `glab mr create --title "..." --description "$(cat <path>)" --source-branch <branch>`. Title in Conventional Commits form (e.g. `feat: ...`). Check `glab label list` for the right tags.
- Open the created MR in the browser so the user can review it there: `glab mr view --web` (on the current branch).
- Write a SHORT review guide to `.pi/mr/<issue#>-<work-name>-guide.md` (git-ignored) and post it as an MR comment: what to review together, what matters most and why — files grouped by relationship, story order. Scannable, not exhaustive. Tell the user the guide's path.
- Then call wait_for_user (prompt "Review the MR and leave comments"; confirmLabel "Pull my comments") instead of explaining at length.
- When the user signals, pull unresolved comments — PAGINATE so none are missed: `glab api projects/:id/merge_requests/:iid/discussions --paginate` (get the iid via `glab mr view --output json` on the current branch). Turn actionable comments into tasks (add_tasks) so they stay in context.
- Fix what's directly fixable and resolve those threads (the user can reopen); answer questions in-thread via `glab api ...merge_requests/:iid/discussions/:id/notes`, prefixing replies with "**Agent**:". Summarize anything left in chat. Resolve each task as its thread is handled.
- Loop (wait_for_user → pull → address) until the user merges. You never merge.
