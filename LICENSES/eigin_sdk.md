# Eigin SDK third-party notices

[Generated SDK notices](../src/eigin_sdk/THIRD-PARTY-NOTICES.txt) are the shared runtime inventory, copyright notices and full license texts. Host application dependencies remain in their own inventories.

## Regeneration

```sh
npm ci
just sdk-notices
just sdk-notices --check
```

Regenerate after changing SDK, CLI or browser runtime dependencies. Commit all generated copies. SDK artifact generation also regenerates notices. `--check` fails on missing texts, missing installed npm packages, or stale output.

The generator resolves normal dependencies from the SDK and CLI Cargo lockfiles for Apple, WebAssembly, macOS/Linux/Windows CLI targets. It combines those graphs with the browser SDK's locked npm runtime dependencies, including peers and optional dependencies. Build dependencies, procedural macros, test dependencies and the bindgen workspace member are excluded. A dependency used by both tooling and runtime remains included.

This is a conservative cross-platform inventory, not a binary-size or linker-reachability report. New target families or non-default shipping features need corresponding generator coverage.

## Text sources

Cargo package archives and installed npm packages supply license, copyright and notice files.

- Identical full license texts appear once in a shared section. Package entries reference them; copyright lines within those texts stay intact.
- For `MIT OR Apache-2.0` (in either order), the generator selects MIT and omits the alternative Apache license file. The MIT text must be present.
- Other license expressions retain their supplied texts. Supplemental copyright, attribution and notice files remain with each package.
- Packages without license text fail generation unless they have an explicitly reviewed, version-pinned fallback.

UniFFI 0.31.0 and the 0.31.0-6 browser runtimes omit their full MPL text from published packages. Their fallbacks use the preserved [upstream MPL text](uniffi/MPL-2.0.txt), the source-file notice and versioned upstream source links. Review these exceptions when updating versions.

## Host distribution

- **Apple:** the `EiginSDK` Swift package bundles the file as a resource and exposes `EiginSDK.thirdPartyNoticesURL`. The generated `NOTICES.json` catalog supplies the SDK version from `config/app.toml`, its AGPL-3.0 text from the repository `LICENSE`, and dependency metadata with shared license texts. iOS presents navigable subitems under Settings → About → Licenses → Eigin SDK, using the same detail screen as direct dependencies.
- **Browser:** the SDK package carries `THIRD-PARTY-NOTICES.txt`. The browser host distributes an identical `SDK-NOTICES.txt` public asset and links to it.
- **CLI:** `eigin notices` prints the shared artifact embedded in the executable.

UniFFI is presented through the grouped Eigin SDK entry, including its source-availability notice and full MPL text. unicode-segmentation is also presented within the SDK group.

Browser test/build tooling is listed in [web packages](web-packages.md).
