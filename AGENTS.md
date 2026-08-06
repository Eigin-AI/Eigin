# Eigin monorepo project
Eigin is the application layer for personal AI: local-first native apps that turn any model into an agent that's truly yours.

## Project structure

- `src/` — all deployable Eigin apps
- `design/` — design tokens, prompts and assets
- `tools/` — Rust CLI for cross-cutting tasks
- `infra/` — infrastructure code
- `justfile` — project commands
- `docs/` — technical documentation
- `LICENSES/` — third-party license attributions

## Prerequisites

See the platform-specific AGENTS file for environment setup: 
- `src/eigin_ios/AGENTS.md`
- `src/eigin_relay/AGENTS.md`

## Build and test

```
just build      # Build all targets
just test       # Run all tests
just format     # Format all code
```

Run `just --list` to see all available commands.

## GitLab

This project uses GitLab for issue tracking and merge requests:

- **Remote:** `dev/eigin` at `code.eigin.ai`
- **CLI:** Use `glab` to interact with issues and MRs from the command line
- **Common commands:**
  - `glab issue list` — list open issues
  - `glab issue view <number> --output json` — fetch issue details
  - `glab mr create` — create a merge request

When working on a task, issues typically provide the problem context and expected behavior. Merge requests should reference their originating issue.

## Documentation

- [`docs/src/introduction.md`](docs/src/introduction.md) — what Eigin is
- [`docs/src/system-context.md`](docs/src/system-context.md) — platform architecture
- [`docs/src/philosophy.md`](docs/src/philosophy.md) — design principles and constraints
- [Full docs index](docs/src/SUMMARY.md)

## Principles

**Formatting** — formatting is standardized and automated. Run `just format` before committing.

**Comments** — document public APIs with summary comments. Use inline comments only for non-obvious logic. Explain what and why, not how. Write for the current state of the code, not what it isn't or how it was. Keep comments short and sharp always.

**Naming** — names should reflect behavior. A name describes what something does, not how it's built.

**Code structure** — prefer small files, a few hundred lines on average. If a file is growing long, split it up. Group related concepts together using folders and modules.

**Testing** — test behavior, not structure. Prefer outside-in tests with real dependencies. When dependencies are slow, unreliable, or unavailable, fake at the boundary. Don't test data models, fakes, or views.

**Optionality** — defer decisions until we have the information to make them well. When the shape of something isn't clear, implement the simplest thing: simple code is cheaper to change than a wrong abstraction. Abstract only when you're confident in the shape and expect the implementation to change underneath. The exception is sticky decisions (persisted schemas, protocol contracts) where optionality is structurally low — invest more care upfront.
