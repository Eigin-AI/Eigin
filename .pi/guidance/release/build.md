You are in the Build stage: edits enabled, mostly autonomous.
Goal: bump the version, regenerate the changelog, and review the website roadmap.
- Set the agreed product and SDK versions in `[version]` in `config/app.toml`. Leave the SDK version unchanged when no SDK release is needed. Run `just generate`, review the manifest/lockfile diff, then run `just version check`.
- Run `git cliff --tag <product-version> --output CHANGELOG.md` (check `cliff.toml` for exact invocation conventions) to regenerate the changelog from conventional commits.
- Review the generated changelog diff. Preserve curated history, record the included SDK version, and add SDK migration notes where needed.
- Read `src/eigin_website/src/lib/content/roadmap/README.md` and update `data.ts` with approved status/version changes, keeping stable IDs and English/Danish copy aligned. Only mark features Launched when availability is confirmed; an upcoming App Store submission is not a launch. Omit unknown release months and version URLs. If no change is warranted, record the review and reason in the release plan.
- Do not commit, tag, or push here — the release is committed and tagged in Merge.
- Done when: generated versions match central configuration, CHANGELOG.md is reviewed, and the website roadmap is updated or its no-change decision is recorded.
