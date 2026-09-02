# Build from source

Eigin is a monorepo. Install the toolchain for the part you want to work on:

- **iOS app**: macOS only. Targets iOS 26, drives `xcodebuild`.
- **Relay and tooling**: anywhere Rust runs, including a Linux container.

## Prerequisites

Required for everything:

- [Rust](https://rustup.rs): every recipe runs through the Rust `tools/` CLI, so it's needed even for iOS-only work.
- [just](https://github.com/casey/just#installation): `cargo install just`, or see the link for other package managers.

For iOS (macOS only):

- [Xcode 17](https://developer.apple.com/xcode/) with the iOS 26 SDK and the **iPhone 17 Pro** simulator.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen#installing): `brew install xcodegen`.
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat#how-do-i-install-it): `brew install swiftformat`.
- Then: `xcode-select -s /Applications/Xcode.app/Contents/Developer`.

Optional:

- [mdBook](https://rust-lang.github.io/mdBook/guide/installation.html): build these docs.
- [Docker](https://docs.docker.com/get-docker/): Postgres tests, deploy image.
- [Terraform](https://developer.hashicorp.com/terraform/install): `just infra`.

## Setup

From the repo root, after cloning, run these three:

```
just hooks         # install git hooks (one-time)
just config init   # create your .env
just generate      # run code generation
```

You can build straight after this. **No secrets need filling in.** App
configuration lives in `config/app.toml`; `.env` is for secrets, and features
that need one are simply inactive until you add it.

`just generate` always produces localization, design tokens, prompts and
knowledge. It also generates the Xcode project when XcodeGen is installed, and
the build server config when Xcode is available. Each Xcode step is skipped with
a note when its tool is missing, so relay and tooling work needs only Rust.

To see where you stand at any point:

```
just config
```

```
iOS app      builds, with limits:
               - EIGIN_RELAY_PRIMARY_KEY_STAGING not set — the staging app will
                 build, but relay features (inference, search, credits) won't work
Local relay  unavailable (...) — expected unless you maintain the relay
Infra        unavailable — expected unless you deploy Eigin
```

The relay and infra secrets are Eigin's own; contributors aren't expected to
have them. Add your own inference provider key in the app at runtime to do real
work without the relay.

Set `DEVELOPMENT_TEAM` in `.env` when you want to build for a physical device;
simulator builds don't need it.

## Build and test

From the repo root; arguments are positional. In a Linux container, scope to `relay` (no `xcodebuild`).

- `just build [ios|relay]`: default all.
- `just test [ios|relay]`: default all.
- `just format`: auto-format.
- `just run relay`: start the relay locally.
- `just --list`: see everything.
