# Guidelines

## Submitting changes

- Keep merge requests focused. One thing at a time.
- Run `just build` and `just test` before you open an MR. It should compile, build, and pass tests.
- Run `just format`. The formatter does what's required, don't hand-format.
- Follow the GitLab merge request template.
- Write a clear description of what changed and why.

## When to update the docs

Update the docs when you change a core feature or introduce a central concept. The code is where we go for specifics. The docs are where we go for concepts, architecture, and why things are the way they are.

## Comments

Use summary comments for classes and functions that matter. Skip them when the code is self-evident.

Add inline comments where something isn't obvious, or to explain what a section of code does and why. Describe the code as it is now, not its history or what it used to be.

Coding agents tend to over-comment. Keep comments short, and avoid ones likely to go stale quickly.

## Writing style

Docs and comments are for someone who doesn't know anything about us or what we're building. The goal is for them to understand what something is, why it exists, and how to work on it. Not to make us look smart.

- Short, direct, warm. No em dashes.
- Prefer short sentences and short prose over long ones.
- Avoid over-explaining and lingering on trade-offs.
- Keep docs scannable.
- Prefer simple words over complicated ones.
