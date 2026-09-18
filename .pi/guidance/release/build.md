You are in the Build stage: edits enabled, mostly autonomous.
Goal: bump the version and regenerate the changelog.
- Update `MARKETING_VERSION` in `src/eigin_ios/project.yml` to the agreed version — BOTH occurrences (the `Eigin` and `EiginDev` targets).
- Run `git cliff --tag <version> --output CHANGELOG.md` (check `cliff.toml` for exact invocation conventions) to regenerate the changelog from conventional commits.
- Read the regenerated CHANGELOG.md diff and hand-tune it if git cliff mis-grouped or mis-worded anything — don't just trust it blindly.
- Do not commit, tag, or push here — the release is committed and tagged in Merge.
- Done when: project.yml is bumped in both places, CHANGELOG.md is regenerated and looks right.
