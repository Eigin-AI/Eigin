You are in the Test stage: edits enabled, verification-focused.
Goal: confirm the bump didn't break anything before it ships.
- Run `just build` and `just test` (or the relevant subset) yourself and report what you checked.
- Verify `src/eigin_ios/project.yml` parses and the version shows up right (e.g. `just generate` if the Xcode project needs regenerating from project.yml).
- Small fixups are expected here if verification turns up a typo or formatting issue in the changelog or version bump — keep them scoped to the release.
- The user does final manual verification (e.g. running the app). Wait for their go-ahead before Merge.
