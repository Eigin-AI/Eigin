# Eigin monorepo project
Eigin is a native app and agent harness built around privacy, ownership, and freedom of choice. Data lives on device. Users bring their own keys and connect to any AI inference provider — or run fully local models. There is no Eigin account, no tracking, and no hidden outbound calls. The relay service is a narrow optional component for features that genuinely require connectivity (e.g. web search); the default orientation is local.

The app is a chat interface, a persistent agent, and an agent harness: users configure an agent with knowledge, skills, and intents that shape how it behaves across conversations.

## Project structure

- `src/` — contains all deployable Eigin applications
  - `src/eigin_ios/` — iOS app (Swift 6, SwiftUI, iOS 26.0)
  - `src/eigin_relay/` — connectivity service (Rust, Axum, Tower)
- `assets/` — shared assets (sound effects, etc.)
- `LICENSES/` — third-party license attributions (ML models, Swift packages, Rust crates)
- `scripts/` — build and maintenance scripts
- `Makefile` — build, test, and project generation commands (at repo root)
- `docs/` — high level documentation

## Prerequisites

See the platform-specific AGENTS file for environment setup: 
- `src/eigin_ios/AGENTS.md`
- `src/eigin_relay/AGENTS.md`

## Build and test

All commands run from the repo root:

```
make generate       # Regenerate .xcodeproj + LSP config

make ios-build      # Generate + build iOS
make ios-test       # Generate + run iOS unit tests
make ios-clean      # Clean iOS build artifacts
make ios-open       # Generate + open Xcode

make relay-build    # Build relay (cargo build --release)
make relay-test     # Run relay tests

make test           # Run all platform tests
make format         # Auto-format all code
make lint           # Lint without modifying
```

## Documentation

- [`docs/src/introduction.md`](docs/src/introduction.md) — what Eigin is
- [`docs/src/system-context.md`](docs/src/system-context.md) — platform architecture
- [`docs/src/philosophy.md`](docs/src/philosophy.md) — design principles and constraints
- [Full docs index](docs/src/SUMMARY.md)

## Workflow

1. **Discuss**: Before starting a new feature, discuss how and why we do it.
2. **Plan**: When we have a rough design, create a plan of action for review.
3. **Implement**: Implement the first pass according to the plan.
4. **Iterate**: Review, test, ask questions, and give feedback for changes.
5. **Test**: Make sure important behaviour is covered by unit tests.
6. **Document**: Make sure important behaviour is documented.

## Principles

**Formatting** — formatting is standardized and automated. Run `make format` before committing. Don't avoid style debates; let the formatter decide.

**Comments** — document public APIs with summary comments. Use inline comments only for non-obvious logic. Explain what and why, not how. Write for the current state of the code — git history covers the rest.

**Naming** — names should reflect behavior, not structural implementation. A name describes what something does, not how it's built.

**Code structure** — prefer small files, a few hundred lines at most. If a file is growing long, consider splitting it. Group related concepts together using folders and modules.

**Testing** — test behavior, not structure. Prefer outside-in tests with real dependencies. When dependencies are slow, unreliable, or unavailable, fake at the boundary. Don't test data models, fakes, or views.

**Optionality** — defer decisions until you have the information to make them well. When the shape of something isn't clear, implement the simplest thing — simple code is cheaper to change than a wrong abstraction. Abstract only when you're confident in the shape and expect the implementation to change underneath. The exception is sticky decisions (persisted schemas, protocol contracts) where optionality is structurally low — invest more care upfront.
