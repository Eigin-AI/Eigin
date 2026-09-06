# App Store metadata

App Store listing, managed as code via `deliver`.

Structure follows [`deliver`'s metadata format](https://docs.fastlane.tools/actions/deliver/#available-metadata-folder-options):
one folder per locale (`en-US/`), one file per field (`subtitle.txt`,
`description.txt`, `keywords.txt`, `release_notes.txt`, ...). No `name.txt` —
app name is a one-time identity setting managed by hand in App Store Connect.

`just release ios <env> metadata` pushes changes without building or
submitting a binary.

Screenshots are not metadata: they are generated from the app and live in
`fastlane/screenshots/` (gitignored), pushed by their own lane. See
[docs/src/ios/screenshots.md](../../../../docs/src/ios/screenshots.md).
