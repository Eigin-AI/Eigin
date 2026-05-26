# Eigin monorepo project
Eigin is the application layer for personal AI: a native app and agent harness built around privacy, ownership, and freedom of choice. Data lives on device. 

Users bring their own keys and connect to any AI inference provider or run fully local models. There is no tracking and no hidden incentives.

## Project structure

- `src/` — contains all deployable Eigin apps
  - `src/eigin_ios/` — iOS app (Swift 6, SwiftUI, iOS 26.0)
  - `src/eigin_relay/` — connectivity service (Rust, Axum, Tower)
- `design/` — design tokens and assets (fonts, icons, app icon, sound effects)
- `LICENSES/` — third-party license attributions (ML models, Swift packages, Rust crates)
- `tools/` — Rust CLI for cross-cutting tasks
- `justfile` — build, test, and project commands
- `docs/` — technical documentation

## Prerequisites

See the platform-specific AGENTS file for environment setup: 
- `src/eigin_ios/AGENTS.md`
- `src/eigin_relay/AGENTS.md`

## Build and test

All commands run from the repo root. After cloning:

```
just hooks      # Install git hooks (one-time)
just generate   # Regenerate the project
```

Then the core loop:

```
just build      # Build all targets
just test       # Run all tests
just format     # Auto-format all code
```

Run `just --list` to see all available commands.

## Workflow

1. **Discuss**: Before starting a new feature, discuss how and why we do it.
2. **Plan**: When we have a rough design, create a plan of action for review.
3. **Implement**: Implement a first pass according to the plan.
4. **Iterate**: Review, test, ask questions, and give feedback for changes.
5. **Test**: Make sure new behaviour is covered by unit tests.
6. **Document**: Make sure new behaviour is documented.

## Documentation

- [`docs/src/introduction.md`](docs/src/introduction.md) — what Eigin is
- [`docs/src/system-context.md`](docs/src/system-context.md) — platform architecture
- [`docs/src/philosophy.md`](docs/src/philosophy.md) — design principles and constraints
- [Full docs index](docs/src/SUMMARY.md)

## Principles

**Formatting** — formatting is standardized and automated. Run `just format` before committing.

**Comments** — document public APIs with summary comments. Use inline comments only for non-obvious logic. Explain what and why, not how. Write for the current state of the code — git history covers the rest.

**Naming** — names should reflect behavior. A name describes what something does, not how it's built.

**Code structure** — prefer small files, a few hundred lines on average. If a file is growing long, split it up. Group related concepts together using folders and modules.

**Testing** — test behavior, not structure. Prefer outside-in tests with real dependencies. When dependencies are slow, unreliable, or unavailable, fake at the boundary. Don't test data models, fakes, or views.

**Optionality** — defer decisions until we have the information to make them well. When the shape of something isn't clear, implement the simplest thing: simple code is cheaper to change than a wrong abstraction. Abstract only when you're confident in the shape and expect the implementation to change underneath. The exception is sticky decisions (persisted schemas, protocol contracts) where optionality is structurally low — invest more care upfront.
