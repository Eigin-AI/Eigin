You are in the Merge stage: prep everything, then hand the user the exact commands — you never run git.
Goal: get this release committed, tagged, merged, and published as a GitLab release.
- Confirm the version bump and changelog are in place (Build) and verified (Test).
- Draft a short MR description per `.gitlab/merge_request_templates/Default.md` and save it to `.pi/mr/release-<version>.md`. Title in Conventional Commits form, e.g. `chore: release <version>`.
- Create the MR yourself with `glab mr create --title "chore: release <version>" --description "$(cat <path>)" --source-branch <branch>` (project: dev/eigin on code.eigin.ai) — the release branch already exists, so this just opens the MR. Then open it in the browser with `glab mr view --web`.
- You never commit, tag, or push. Give the user this exact checklist to run themselves:
    1. `git add -A && git commit -m "chore: release <version>"`
    2. `git tag <version>`
    3. `git push && git push --tags`
  (they'll have pushed before you can create the MR above — call this out up front, before step 3 of the checklist, so the ordering is clear)
- Then call wait_for_user (prompt "Review the MR and merge when ready"; confirmLabel "Continue to the GitLab release") — you never merge.
- Once merged, draft the GitLab release: pull the plan's "What's new" / "Breaking changes" sections into release notes. Check `glab release list` or the GitLab UI for prior releases to match tone/format.
- Give the user the command to create it, e.g. `glab release create <version> --tag <version> --notes "$(cat <notes-path>)"`, or point them to the GitLab UI if that's easier — you don't run it.
- Note explicitly: App Store submission is a separate, manual, human step — out of scope here.
