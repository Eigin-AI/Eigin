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

## Signing with match

[Fastlane match](https://docs.fastlane.tools/actions/match/) reads encrypted App
Store assets from a separate private GitLab repository (`main` branch).
The ASC API key needs **App Manager** access. Development signing is automatic;
`archive` passes per-target manual signing settings through `gym`; `beta` uploads its IPA.

### Configure

Set in `.env` or inject into the process; keep passwords and keys in the secret manager:

```sh
export MATCH_GIT_URL=git@code.eigin.ai:dev/ios-signing.git  # use your private repo
export MATCH_PASSWORD='your-signing-password'
export MATCH_GIT_PRIVATE_KEY=/absolute/path/outside/checkout/signing_key  # optional locally
```

### Import and renew

With maintainer write access to the signing repository:

1. Export the distribution `.cer` and private key. For match, prepare an
   unencrypted PEM private key with a `.p12` filename (Fastlane's native format).
   Keep it outside the checkout and remove after import. Cloud-managed keys may
   require an exportable identity from an Admin.
2. Download App Store profiles for each bundle ID below, using that certificate.
3. Export configuration and import each profile; Fastlane prompts for the asset paths:

   ```sh
   # Repository root; keep shell tracing off.
   eval "$(cargo run --quiet --manifest-path tools/Cargo.toml -- config export ios)"
   cd src/eigin_ios
   bundle exec fastlane match import --type appstore --readonly false
   ```

| Target | Production | Staging |
|---|---|---|
| App | `${BUNDLE_ID}` | `${BUNDLE_ID}.dev` |
| Widgets | `${BUNDLE_ID}.widgets` | `${BUNDLE_ID}.dev.widgets` |
| Watch app | `${BUNDLE_ID}.watchkitapp` | `${BUNDLE_ID}.dev.watchkitapp` |
| Complications | `${BUNDLE_ID}.watchkitapp.widgets` | `${BUNDLE_ID}.dev.watchkitapp.widgets` |

Repeat renewal at least yearly or when warned: renew through Apple Developer,
re-import, and verify before old assets expire. Use maintainer Apple login for
import validation; keep CI access read-only. Never use `match nuke` or commit
unencrypted assets. Remove temporary exports after import.

### Check and use in CI

With configuration exported, run from `src/eigin_ios/`:

```sh
bundle exec fastlane ios check_signing env:staging
bundle exec fastlane ios check_signing env:production
```

Checks install assets without building/uploading. Both release and check lanes
use read-only match, warn within **30 days** of profile/certificate expiry, and
fail on expired or missing assets. Offline checks cannot detect revocation.

- Use a trusted macOS runner with Xcode, XcodeGen, Ruby 3.3.0, and Bundler.
- Give CI a dedicated **read-only SSH deploy key** (`0600`, outside checkout),
  verified GitLab host keys in `known_hosts`, and protected signing/ASC secrets.
  Set `DEVELOPMENT_TEAM` in the runner's `.env` when using `just release`.
- Set `CI=true` for temporary keychains in check-only runs too. Archive builds
  retrieve assets before restricting signing to a temporary default keychain and
  exclusive user search list, restoring both on exit.
  Isolate runner users per job; keep secrets away from untrusted branch jobs.
- Prepare build inputs from the repository root with `just generate ios`.
  Then run `bundle exec fastlane ios archive env:staging` from `src/eigin_ios/`
  (or `env:production`) to archive/export without uploading. Inspect the exported
  app and embedded signatures. `beta` also uploads to TestFlight.
- Schedule the check lane for expiry monitoring. Rotate deploy keys through the
  secret manager; rotate encryption with `fastlane match change_password` using
  maintainer access. Old Git history retains old encryption; review revocation
  with the account owner after compromise.

## Submitting to the App Store

There's no dedicated "submit" lane — submitting is a manual process for now.
We may automate more of it later, once we have more experience with the
release flow.

1. `just release ios production beta` — get a build to TestFlight.
2. Attach that build to an App Store version in App Store Connect.
3. `just release ios production metadata` — push listing copy, if changed.
4. Submit for review by hand.

## Version numbers

Marketing version comes from `[version].product` in `config/app.toml`. Edit it
once, run `just generate ios`, review the diff, then run `just version check`.
Generation synchronizes version metadata; release preparation checks it before publishing. Build
number is derived automatically (latest TestFlight build + 1).

See [Names and versioning](../contributing/naming.md#versioning) for the shared
product/SDK policy and release checklist.

## Store configuration as code

- App Store listing metadata (`fastlane/metadata/`) and in-app purchases
  (`fastlane/iap/*.yml`) both target either app via `env:`.
- IAP product IDs and credit amounts must stay in sync with
  `src/eigin_relay/config/products.toml`, the source of truth for what the
  relay grants.
- IAP sync is create/update only — Apple exposes no deletion API. Remove
  retired products by hand in App Store Connect.

See `src/eigin_ios/fastlane/README.md` for lane-level detail.
