# LiteRTLM (vendored)

This is a local Swift package vendoring the Swift wrapper sources from
[google-ai-edge/LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM), Apache 2.0
licensed. Vendored from the `v0.16.0` release tag.

## Why vendored instead of a remote SPM dependency

Consuming the package directly as a remote git dependency required three build-time
workarounds (see [issue #131](https://code.eigin.ai/dev/eigin/-/work_items/131)):

1. LiteRT-LM ships Android/Windows prebuilt binaries via Git LFS, but the LFS blobs are
   missing from storage — see upstream
   [google-ai-edge/LiteRT-LM#2407](https://github.com/google-ai-edge/LiteRT-LM/issues/2407).
   A stock SPM checkout aborts with `Couldn't check out revision ...`. We don't use those
   binaries; `Package.swift` pulls the iOS/macOS `CLiteRTLM.xcframework` from a GitHub
   Release instead.
2. `Conversation` has no explicit teardown method upstream (only `deinit`), so we had to
   patch the resolved checkout's source in place at codegen time to add one.
3. The `CLiteRTLM.framework` ships as a prebuilt dynamic framework with no companion
   dSYM (still true as of v0.16.0), requiring a post-build `dsymutil` step regardless of
   how the package is consumed — see `Generate dSYM for CLiteRTLM` in
   `src/eigin_ios/project.yml`.

Vendoring the Swift sources and pulling the XCFramework as a `binaryTarget` sidesteps (1)
and (2) entirely: there's no git clone of the upstream repo, so no LFS checkout to fail,
and `close()` (below) is a normal committed source change instead of an in-place patch
applied by `tools/src/generate.rs` on every `just generate`. (3) is unrelated to how the
package is consumed and remains handled by the post-build script.

## Local modifications

- **`Sources/LiteRTLM/Conversation.swift`** — added `Conversation.close()`, which calls
  `litert_lm_conversation_delete` synchronously and nils out the handle. LiteRT-LM allows
  only one active session per engine, and Swift's ARC does not guarantee synchronous
  deallocation across async suspension points, so callers (`GemmaRuntime.swift`) need an
  explicit way to release the previous session before creating the next one.
- Test targets (`*Tests.swift`, `BUILD`, `Info.plist`) are not vendored — we don't run
  upstream's test suite here.

## Bumping the vendored version

1. Pick the target release tag upstream (e.g. `v0.14.0`) and note its `Package.swift`
   `binaryTarget` URL + checksum for the platform(s) we ship.
2. Re-copy the non-test files from that tag's `swift/` directory into
   `Sources/LiteRTLM/`.
3. Re-apply the `close()` addition to `Conversation.swift` (diff against the previous
   vendored copy to carry forward any other local changes).
4. Update `Package.swift`'s `binaryTarget` url/checksum.
5. Update the revision/version noted at the top of this file and in
   `LICENSES/swift-packages.md`.
6. Run `just generate && just build ios && just test ios`.

Keep these sources verbatim in upstream's style so the diff against a new tag
stays clean. `just format` does not touch them and `src/eigin_ios/.swiftformat`
excludes `Packages/LiteRTLM` from the lint (see the comment there).
