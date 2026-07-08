# Development environment

Eigin is a monorepo. Install the tools for the part you're working on. See [Build from source](./build-from-source.md) for the full prerequisite list, including iOS.

## Required for everything

- [just](https://github.com/casey/just): the command runner. Every task in the repo runs through it.
- [Rust](https://rustup.rs): the toolchain. Every `just` recipe runs through the Rust `tools/` CLI, even for iOS-only work.

## The pi coding agent

We build with [pi](https://pi.dev/), a coding agent, and ship an `eigin` extension in `.pi/` that implements our workflow: stages, guardrails, and conventions specific to how we work. We keep it current and use it ourselves.

Working the way we work makes your contribution coherent with the rest of the codebase, and more likely to get merged.

To use it:

1. Install pi from [pi.dev](https://pi.dev/).
2. Open this repo with pi.
3. Trust the `eigin` extension when prompted.

## Zed

We use the [Zed](https://zed.dev/) editor and ship basic settings in `.zed/`, including SwiftFormat on save. Optional but recommended. Any editor works.

## Install git hooks

```
just hooks
```

One-time setup. Once this runs, you're ready to build.
