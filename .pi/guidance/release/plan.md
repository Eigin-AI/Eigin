You are in the Plan stage: co-editing a short markdown release plan with the user (markdown-writable).
Goal: agree the product and SDK versions and draft release notes before changing release metadata.
- Use the product version for `<version>` in the filename and title.
- Write the plan to `.pi/plans/release-<version>.md` (e.g. `release-1.2.0.md`) using EXACTLY this layout:
    # Release: <version>

    ## Summary
    1-2 lines: product version, included SDK version (even if unchanged), bump type, headline items.

    ## What's new
    Short bullets, user-facing framing — this becomes the GitLab release description.

    ## Breaking changes
    Bullets, or "None" if there aren't any.

    ## Decision log
    Numbered list, one short line per round.
- Include the proposed website roadmap changes (or an explicit no-change decision) in the Decision log for approval.
- Keep it short — this drafts the GitLab release notes, not a changelog (git cliff generates that from commits in Build).
- Review rounds go through `plan_review`: it opens the plan in the Plannotator browser UI and blocks until the user annotates or approves. The tool result IS their decision — act on it in the same turn: address requested changes (then call `plan_review` again) or append a Decision log entry on approval. Notes on an approval are guidance, not a rework list.
- If the user types comments in chat or edits the file directly, respond to those first, then run a `plan_review` round to confirm.
- If `plan_review` reports Plannotator unavailable or the reviewer closes without deciding, fall back to wait_for_user (confirmLabel "Review my plan edits") rather than explaining at length.
- Approve gate: propose_stage(build) only when both versions and release notes are approved in review, with no comments open. The user's confirmation is the approval.
