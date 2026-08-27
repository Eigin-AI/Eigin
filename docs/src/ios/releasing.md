# Releasing

iOS releases are managed with [Fastlane](https://fastlane.tools), driven
through `just release`.

## Prerequisites

- Ruby 3.3.0 via [rbenv](https://github.com/rbenv/rbenv) and Bundler. See
  `src/eigin_ios/fastlane/README.md` for setup and troubleshooting.
- An App Store Connect API key (Users and Access → Integrations → App Store
  Connect API), set in `.env`:

  ```
  export ASC_KEY_ID=...
  export ASC_ISSUER_ID=...
  export ASC_KEY_PATH=fastlane/AuthKey/AuthKey_XXXX.p8
  ```

## Profiles: staging vs production

Releases are separated by the same `staging`/`production` selector as `just
build ios`. Scheme and bundle ID are derived from it:

| | `staging` | `production` |
|---|---|---|
| Scheme | `EiginDev` | `Eigin` |
| Bundle ID | `${BUNDLE_ID}.dev` | `${BUNDLE_ID}` |

A future internal, white-label, or private release is just a different
`BUNDLE_ID` / `DEVELOPMENT_TEAM` behind the same lanes — not a new mechanism.

## Commands

```
just release                          # staging -> TestFlight, defaulting to least public
just release ios staging beta         # same, explicit
just release ios production beta      # production -> TestFlight
just release ios production metadata  # push App Store listing copy only
just release ios staging iap          # push in-app purchase definitions
```

Signing is automatic (cloud-managed) via the App Store Connect API key — no
certificates to manage by hand. This works because our distribution
certificate's private key persists in this machine's keychain across runs.
An ephemeral CI runner wouldn't have that: a certificate's private key only
ever lives on the machine that created it, so a fresh runner can't reuse one.
`fastlane match` solves that (tracked as part of the CI/CD pipeline work).

## Submitting to the App Store

There's no dedicated "submit" lane — submitting is a manual process for now.
We may automate more of it later, once we have more experience with the
release flow.

1. `just release ios production beta` — get a build to TestFlight.
2. Attach that build to an App Store version in App Store Connect.
3. `just release ios production metadata` — push listing copy, if changed.
4. Submit for review by hand.

## Version numbers

Marketing version is set by hand in `project.yml`, once per release. Build
number is derived automatically (latest TestFlight build + 1).

## Store configuration as code

- App Store listing metadata (`fastlane/metadata/`) and in-app purchases
  (`fastlane/iap/*.yml`) both target either app via `env:`.
- IAP product IDs and credit amounts must stay in sync with
  `src/eigin_relay/config/products.toml`, the source of truth for what the
  relay grants.
- IAP sync is create/update only — Apple exposes no deletion API. Remove
  retired products by hand in App Store Connect.

See `src/eigin_ios/fastlane/README.md` for lane-level detail.
