# Build from source

Install the toolchain for the source project you want to work on:

| Project | Development host | Toolchain |
|---|---|---|
| iOS app | macOS | Rust, Xcode 26 / iOS 26 SDK, XcodeGen, SwiftFormat |
| SDK | macOS or Linux | Rust 1.99.1; Node/npm for browser bindings, Xcode for Apple bindings |
| CLI | macOS or Linux | Rust 1.99.1 |
| Relay and repository tools | Anywhere Rust runs | Rust; Docker for database tests |
| Website, web test host, design gallery | macOS or Linux | Rust, Node.js 22.17+, npm 10+ |

## Prerequisites

| Tool | Installation / setup |
|---|---|
| [Rustup](https://rustup.rs) | Required by repository commands; SDK and CLI toolchains are pinned |
| [just](https://github.com/casey/just#installation) | `cargo install just` |
| [Xcode 26](https://developer.apple.com/xcode/) | Install iOS 26 SDK and iPhone 17 Pro simulator; run `xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen#installing) | `brew install xcodegen` |
| [SwiftFormat](https://github.com/nicklockwood/SwiftFormat#how-do-i-install-it) | `brew install swiftformat` |
| [Node.js](https://nodejs.org/) | With nvm: `nvm install 24 && nvm use 24` |
| Browser test engines | After web generation: `npx playwright install chromium firefox webkit`; add `--with-deps` on Linux |
| Optional tools | [mdBook](https://rust-lang.github.io/mdBook/guide/installation.html) for docs, Docker for Postgres tests, Terraform for infrastructure work |

## Setup

Run from the repository root:

| Command | Purpose |
|---|---|
| `just hooks` | Install git hooks once |
| `just config init` | Create `.env` |
| `just generate ios` | Prepare Apple SDK artifacts, iOS sources, and Xcode project |
| `just generate web` | Restore missing npm tooling, generate web assets and browser SDK artifacts |
| `just generate sdk web` | Prepare browser SDK artifacts only |
| `just generate` | Generate all targets; requires both Apple and web toolchains |
| `just config` | Show configuration status |

Web generation runs `npm ci` when required tooling is missing. Run `npm ci` explicitly after changing the npm lockfile.
Relay-only work requires no generation. SDK setup details are in the [SDK guide](https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_sdk/README.md).

App configuration lives in `config/app.toml`; `.env` holds secrets. Features needing missing secrets stay inactive. Contributors can add their own inference provider key in the app without relay credentials.
Set `DEVELOPMENT_TEAM` in `.env` for physical-device builds; simulator builds do not need it.

## Build and test

Arguments are positional; build and test default to all targets. On Linux, select `relay`, `sdk`, `cli`, or `web`.

| Command | Scope |
|---|---|
| `just build [ios\|relay\|web\|sdk\|cli]` | Build the selected target; `web` builds all npm workspaces |
| `just test [ios\|relay\|web\|website\|sdk\|cli]` | Run target checks; `website` includes website browser tests |
| `just test-sdk-apple` | Independent Swift package and binding tests |
| `just generate [all\|ios\|web\|sdk]` | Generate selected outputs; `sdk [apple\|web\|all]` selects host artifacts |
| `just format` | Format source code |
| `just --list` | List all commands |

## Run

UI and server commands start a detached process. The CLI runs in the foreground.

| Command | Target |
|---|---|
| `just run ios simulator [env]` | iPhone 17 Pro simulator |
| `just run ios device [device] [env]` | Paired iPhone |
| `just run relay [env]` | Local relay |
| `just run web gallery` | Design gallery at localhost:5173; default web target |
| `just run web site` | Website at localhost:5174 |
| `just run web app` | SDK browser test host at localhost:5175 |
| `just run cli init` | Headless SDK initialization |
| `just logs web [gallery\|site\|app]` | Web logs |
| `just stop web [gallery\|site\|app]` | Stop web target |
| `just logs relay [since] [--follow]` | Relay logs |
| `just stop relay` | Stop relay |
| `just logs ios simulator [env] [since] [--follow]` | Simulator logs |
| `just logs ios device [device] [env] [since]` | Device logs |

`since` accepts durations such as `10m` or a date, and defaults to the last ten minutes.
Device runs need an unlocked, awake phone on the same network. The selected device is remembered; `EIGIN_DEVICE` overrides it for a session.
For web components and browser tests, see [Design system — Web](../design.md#web).
