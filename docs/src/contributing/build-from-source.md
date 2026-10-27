# Build from source

Eigin is a monorepo. Install the toolchain for the part you want to work on:

- **iOS app**: macOS only. Targets iOS 26, drives `xcodebuild`.
- **Relay and tooling**: anywhere Rust runs, including a Linux container.
- **Website and web gallery**: Node.js on macOS or Linux; shared components live in `design/web/`.

## Prerequisites

Required for everything:

- [Rust](https://rustup.rs): every recipe runs through the Rust `tools/` CLI, so it's needed even for iOS-only work.
- [just](https://github.com/casey/just#installation): `cargo install just`, or see the link for other package managers.

For iOS (macOS only):

- [Xcode 17](https://developer.apple.com/xcode/) with the iOS 26 SDK and the **iPhone 17 Pro** simulator.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen#installing): `brew install xcodegen`.
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat#how-do-i-install-it): `brew install swiftformat`.
- Then: `xcode-select -s /Applications/Xcode.app/Contents/Developer`.

For the website and web gallery:

- [Node.js](https://nodejs.org/) **22.17 or newer**, with npm **10 or newer**. With [nvm](https://github.com/nvm-sh/nvm): `nvm install 24 && nvm use 24`.
- Run `npm ci` from the repository root to install both workspaces from the shared lockfile.
- For browser tests: `npx playwright install chromium webkit` (add `--with-deps` on Linux).

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

- `just build [ios|relay|web]`: default all; `web` builds the gallery and static website.
- `just test [ios|relay|web|website]`: default all; `web` checks/builds both workspaces, `website` also runs the website browser tests.
- `just generate [all|ios|web]`: default all; `web` generates shared web assets only.
- `just format`: auto-format.
- `just --list`: see everything.

## Run

`just run` starts a target and returns, `just logs` reads its output, `just stop` ends it.

```
just run relay [env]                            # detached, logs to logs/relay.log
just run ios simulator [env]                    # the iPhone 17 Pro simulator
just run ios device [device] [env]              # a paired iPhone, over the network
just stop relay
just logs relay [since] [--follow]
just logs ios simulator [env] [since] [--follow]
just logs ios device [device] [env] [since]
just run web gallery                           # gallery on localhost:5173
just run web site                              # website on localhost:5174
just logs web [gallery|site]
just stop web [gallery|site]
```

`since` is a duration (`30s`, `10m`, `2h`, `7d`) or a date, and defaults to the
last 10 minutes. Arguments are recognised by shape, so their order is free.

The website and gallery run independently. See [Design system — Web](../design.md#web) for builds, content guidance, and browser tests.

Device runs need `DEVELOPMENT_TEAM` and a phone that's unlocked, awake and on
the same network. Name it once and it's remembered (`logs/device-default`);
`EIGIN_DEVICE` overrides for a session, and several paired phones with no
default means you're asked.
