# Build from source

Eigin is a monorepo. Install the toolchain for the part you want to work on:

- **iOS app** builds on macOS only. Targets iOS 26, drives `xcodebuild`.
- **Relay and tooling** build anywhere Rust runs, including a Linux container.

## Prerequisites

Required for everything:

- [Rust](https://rustup.rs) — every recipe runs through the Rust `tools/` CLI, so
  it's needed even for iOS-only work
- [just](https://github.com/casey/just#installation) — `cargo install just`, or
  see the link for other package managers

For iOS (macOS only):

- [Xcode 17](https://developer.apple.com/xcode/) with the iOS 26 SDK and the
  **iPhone 17 Pro** simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen#installing) — `brew install xcodegen`
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat#how-do-i-install-it) — `brew install swiftformat`
- Then: `xcode-select -s /Applications/Xcode.app/Contents/Developer`

Optional:

- [mdBook](https://rust-lang.github.io/mdBook/guide/installation.html) — build these docs
- [Docker](https://docs.docker.com/get-docker/) — Postgres tests, deploy image
- [Terraform](https://developer.hashicorp.com/terraform/install) — `just infra`

## Setup

From the repo root, after cloning:

- `cp .env.example .env` — you need this; every recipe loads it
- `just hooks` — you probably want this; installs git hooks (one-time)
- `just generate` — required; generates the Xcode project and other codegen

Then open, build, or test.

## Build and test

From the repo root; arguments are positional. In a Linux container, scope to
`relay` since there's no `xcodebuild`.

- `just build [ios|relay]` — default: all
- `just test [ios|relay]` — default: all
- `just format` — auto-format
- `just run relay` — start the relay locally
- `just --list` — see everything
