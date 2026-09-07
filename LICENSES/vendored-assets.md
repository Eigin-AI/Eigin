# Vendored Asset Licenses

Third-party assets whose source we embed directly (not pulled from a package registry at build/runtime).

| Asset | Repository | Version | License | Used by |
|-------|-----------|---------|---------|---------|
| @scalar/api-reference (standalone browser bundle) | https://github.com/scalar/scalar | 1.65.1 | MIT | `src/eigin_relay/assets/scalar-api-reference.js`, served same-origin from `GET /docs` |
| MingCute Icon | https://github.com/MingcuteDesign/MingCute | 3.x | Apache-2.0 | `design/assets/icons/functional/*.svg` |
| SnapshotHelper.swift | https://github.com/fastlane/fastlane | 1.30 | MIT | `src/eigin_ios/EiginUITests/SnapshotHelper.swift`, drives fastlane snapshot from the screenshot UI tests |
| Simple Icons | https://github.com/simple-icons/simple-icons | 15.x | CC0-1.0 | `design/assets/icons/service/*.svg`, brand marks for connectable services |
| Provider brand marks | Sourced from each provider's own brand assets | — | Trademarks of their owners | `design/assets/icons/provider/*.svg`, marks for the AI providers Eigin can connect to |

## Brand marks

`design/assets/icons/provider/` and `design/assets/icons/service/` hold the marks
of companies Eigin can connect to. Most files under `service/` come from Simple
Icons and are CC0; the files under `provider/` were taken from each company's own
brand assets, since most AI providers are not in Simple Icons.

`service/microsoft.svg` is neither: Simple Icons removed the Microsoft marks
after a trademark request, so it is redrawn here as the four squares of the
company logo, monochrome like the rest of the set. The arrangement is a simple
geometric figure, below the threshold of copyright; the mark itself remains
Microsoft's trademark.

Either way the marks themselves stay the trademarks of their owners. Eigin
shows them only to identify which service a connection points at, which is
nominative use and not a claim of endorsement or affiliation.
