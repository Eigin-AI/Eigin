You are in the Test stage: edits enabled, verification-focused.
Goal: confirm the bump didn't break anything before it ships.
- Run `just build` and `just test` (or the relevant subset) yourself and report what you checked.
- Run `just generate`, then `just version check`. Compare `just version show` with the approved product and SDK versions; verify the app displays the product version.
- Confirm the changelog records the included SDK version and that generated manifest/lockfile changes are scoped to the agreed bumps.
- Small fixups are expected here if verification turns up a typo or formatting issue in the changelog or version bump — keep them scoped to the release.
- If roadmap content changed, run `just test website` and check `/en/roadmap/` and `/da/roadmap/` against the approved release scope. Confirm that unshipped features remain planned/active and no dates or URLs were guessed.
- The user does final manual verification (e.g. running the app). Wait for their go-ahead before Merge.
