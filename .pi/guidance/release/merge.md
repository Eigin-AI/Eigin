# Merge stage

Open the GitLab MR, then hand off the git commands and publish the release.

The merge action itself is always manual, performed by the user.
Per `.pi/guidance/git-policy.md`, you commit and push the worktree branch yourself; history-rewriting and remote mutations stay with the user.

Signpost briefly what you expect the user to do — keep the flow tight and self-evident.

## Open the MR

0. Commit, tag, and push the release — the tag must be on the remote before
   the GitLab release can be cut:
    1. `git add -A && git commit -m "chore: release <version>"`
    2. `git tag <version>`
    3. `git push && git push --tags`
1. Confirm the version bump and changelog are in place (Build) and verified (Test).
2. Draft the MR description — follow `.gitlab/merge_request_templates/Default.md`,
   matched to the length and tone of this example `.pi/guidance/mr-example.md`.
    - Keep it short and concise.
    - Focus on what the release contains;
      leave specifics to the changelog.
    - No design history, no decision log.
    - Avoid referencing gitignored artifacts such as in `.pi/plans/` and `.pi/mr/`.
3. Save to `.pi/mr/release-<version>.md`.
4. Create the MR (project: dev/eigin on code.eigin.ai) — the release branch already
   exists, so this just opens it:
   `glab mr create --title "chore: release <version>" --description "$(cat <path>)" --source-branch <branch>`
    - Title is exactly `chore: release <version>`.
5. Open it for the user: `glab mr view --web`.

## Publish the release

Once merged:

1. Draft the release notes: pull the plan's "What's new" / "Breaking changes" sections.
2. Check `glab release list` or the GitLab UI for prior releases to match tone/format.
3. Give the user the command to create it, e.g.
   `glab release create <version> --tag <version> --notes "$(cat <notes-path>)"` —
   or point them to the GitLab UI if that's easier. You don't run it.
4. Note explicitly: App Store submission is a separate, manual, human step.
