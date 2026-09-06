# Vendored Asset Licenses

Third-party assets whose source we embed directly (not pulled from a package registry at build/runtime).

| Asset | Repository | Version | License | Used by |
|-------|-----------|---------|---------|---------|
| @scalar/api-reference (standalone browser bundle) | https://github.com/scalar/scalar | 1.65.1 | MIT | `src/eigin_relay/assets/scalar-api-reference.js`, served same-origin from `GET /docs` |
| MingCute Icon | https://github.com/MingcuteDesign/MingCute | 3.x | Apache-2.0 | `design/assets/icons/functional/*.svg` |
| SnapshotHelper.swift | https://github.com/fastlane/fastlane | 1.30 | MIT | `src/eigin_ios/EiginUITests/SnapshotHelper.swift`, drives fastlane snapshot from the screenshot UI tests |
