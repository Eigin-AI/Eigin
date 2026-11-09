# Fastlane

Build/release automation for the iOS app, underlying the `just release ios`
commands — see [docs/src/ios/releasing.md](../../../docs/src/ios/releasing.md)
for the full guide.

## Setup

Requires Ruby 3.3.0 via [rbenv](https://github.com/rbenv/rbenv)
(`.ruby-version` is committed):

```
brew install rbenv
echo 'eval "$(rbenv init - zsh)"' >> ~/.zshrc   # or ~/.bashrc
```

Open a new terminal, then from `src/eigin_ios/`:

```
rbenv install 3.3.0
gem install bundler
bundle install
```

Requires the App Store Connect API key vars in `.env`
(`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`) — see `.env.example`. The `.p8`
key file itself goes in `fastlane/AuthKey/` (gitignored) — see its README.

## Lanes

All lanes take `env:staging` or `env:production` (default `staging`), matching
`just build ios <env>`. Run via `bundle exec fastlane ios <lane> env:<env>`.

| Lane | What it does |
|---|---|
| `archive` | Build and export an IPA with an isolated keychain; no upload |
| `beta` | Run `archive`, then upload its IPA to TestFlight |
| `check_signing` | Install and check signing assets without building or uploading |
| `screenshots` | Capture App Store screenshots by running the UI tests against `EiginDev` |
| `sync_screenshots` | Push `screenshots/` to App Store Connect, no binary |
| `sync_metadata` | Push `metadata/` listing copy only, no binary |
| `sync_iap` | Push `iap/*.yml` in-app purchase definitions |

There's no separate "submit to App Store" lane — see `docs/src/ios/releasing.md`
for why, and the actual submission workflow.

## Layout

- `Appfile` — identity from `BUNDLE_ID`/`DEVELOPMENT_TEAM`.
- `Fastfile` — lane definitions; `profile(env)` derives scheme/bundle
  id/team from `env`.
- `Deliverfile` — App Store metadata defaults.
- `Snapfile` — `snapshot` config: `EiginScreenshots` scheme (builds `EiginDev`,
  runs `EiginUITests`), `en-US`, 6.9-inch iPhone.
- `metadata/` — App Store listing copy, one folder per locale.
- `screenshots/` — generated captures (gitignored); see
  [docs/src/ios/screenshots.md](../../../docs/src/ios/screenshots.md).
- `iap/*.yml` — in-app purchase definitions.
- `actions/sync_in_app_purchases.rb` — custom action backing `sync_iap`.
- `AuthKey/` — App Store Connect API key (gitignored).

App Review contact info comes entirely from env vars
(`APP_REVIEW_FIRST_NAME`/`_LAST_NAME`/`_PHONE_NUMBER`, `EIGIN_SUPPORT_EMAIL`),
not a committed file — the phone number is personal/sensitive. All have
bogus defaults so `sync_metadata` runs out of the box; set real values in
`.env` before an actual submission. Also required to avoid a real bug:
without any review contact info, `deliver` crashes with an opaque `No data`
error on any version that's never had one — a known, unfixed upstream bug
([fastlane/fastlane#20538](https://github.com/fastlane/fastlane/issues/20538)).

## Signing

Release signing uses encrypted assets from a separate private GitLab repository
through `match(type: "appstore", readonly: true)`. Configure `MATCH_GIT_URL` and
`MATCH_PASSWORD`; optionally set `MATCH_GIT_PRIVATE_KEY` to an absolute file path
outside the checkout. Local SSH access can use your normal key. CI uses a
read-only deploy key. Archive builds use an isolated temporary keychain locally
and in CI after retrieving assets with the user's repository credentials;
cleanup restores the original default keychain and search list. The ASC API key stays App Manager.

The check lane needs signing configuration, `BUNDLE_ID`, and `DEVELOPMENT_TEAM`;
it does not need an ASC key. Direct Bundler commands require exporting configuration
first. See [the release guide](../../../docs/src/ios/releasing.md#signing-with-match)
for import, SSH host verification, renewal, clean-runner validation, and CI setup.

`project.yml` defines per-target profile settings; `beta` supplies their values
through `gym` build arguments. `signing.rb` handles expiry checks and CI keychain
cleanup. Development signing stays automatic. Warnings begin
30 days before expiry; expired assets fail. No scheduled notification job is added.

Run signing behavior tests from `src/eigin_ios/`:

```sh
bundle exec ruby fastlane/tests/signing_test.rb
```
