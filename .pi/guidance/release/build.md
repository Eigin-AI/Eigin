You are in the Build stage: edits enabled, mostly autonomous.
Goal: bump the version, regenerate the changelog, and review the website roadmap.
- Update `MARKETING_VERSION` in `src/eigin_ios/project.yml` to the agreed version — BOTH occurrences (the `Eigin` and `EiginDev` targets).
- Run `git cliff --tag <version> --output CHANGELOG.md` (check `cliff.toml` for exact invocation conventions) to regenerate the changelog from conventional commits.
- Read the regenerated CHANGELOG.md diff and hand-tune it if git cliff mis-grouped or mis-worded anything — don't just trust it blindly.
- Read `src/eigin_website/src/lib/content/roadmap/README.md` and update `data.ts` with approved status/version changes, keeping stable IDs and English/Danish copy aligned. Only mark features Launched when availability is confirmed; an upcoming App Store submission is not a launch. Omit unknown release months and version URLs. If no change is warranted, record the review and reason in the release plan.
- Do not commit, tag, or push here — the release is committed and tagged in Merge.
- Done when: project.yml is bumped in both places, CHANGELOG.md is regenerated and looks right, and the website roadmap is updated or its no-change decision is recorded.
