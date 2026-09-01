# Review guide

The things we ask for on nearly every MR. A reviewer reads this against the
diff so they get said once here instead of every time in review.

Grown by hand: when you catch yourself repeating a comment on an MR, add a
line. Keep each item one line and checkable.

## How to review

- Judge the diff against the plan and the issue. Don't review code the branch didn't touch.
- Severity: **must** (breaks or violates a rule below), **should**, **consider**. Lead with must.
- Cite `file:line` and quote the offending text. A finding you can't point at isn't one.
- Cap at ~10 findings. A few sharp and relevant comments beats a long list.
- No findings is a valid result. Say that and stop - LGTM.
- Skip formatting issues. Skip praise and change summaries.

## Comments and prose

### Comments should describe the code as it is now.
Avoid "used to", "no longer", "previously", "instead of the old" — the comment outlives the change it narrates.

### Comments should be one line, unless they're a doc summary.
`///` summaries stay short too.

### Comments shouldn't restate what the name already says.
If the name carries it, the comment can be deleted.

### Comments shouldn't say the same thing many times.
Across a comment and its code, or across two files.

### Comments and docs should leave out background that isn't needed to understand or act on the code.
Explain what and why, not the tour.

### Comments and docs should say what a thing is, not what it isn't.
Flag "not X, but Y" framing and negative definitions.

## Docs

### Docs should match the style and tone of nearby docs.
Runbooks, for example, are usually short and action-oriented.

### Docs should only claim what's true and consistent with the change.
Flag statements that aren't apparent in the code diff.

### Docs should prefer a layout, table, or list over prose paragraphs.
The key is to make each doc feel immediately scannable by mixing media and using good spacing instead of long blocks of prose.

### Docs should state requirements concretely: which version, via which tool.

## Code

### Two values that always vary together should be one concept.
Flag parallel flags, enums, and params.

### Code should be the simplest thing that works.
Flag uncessesary indirection that could be achieved more simply.

### Code should keep options open.
Flag abstractions or interfaces built for a use case that doesn't exist yet. Sticky decisions (persisted schemas, protocol contracts) are the exception.

### Function names should describe behaviour in the domain, not the mechanism.
Extracted helpers are the usual offenders.

### Defaults should never silently point at production.
Prefer failing loudly on unknown config.

### Code shouldn't carry debug logging left over from the branch.
Scan added lines for `print(`, `NSLog`, `plog`, `dump(`.

### Code shouldn't be temporary.
It's worth doing it right. If something needs to change later, there should be a gitlab issue tracking it.

### Prompt text should live in `design/prompts/`.
Not inline in the code.

## Tests

### Tests should assert behaviour, not specific config values.
Flag exact-match assertions over catalogs and fixtures.

### Tests should be outside-in.
Drive the thing from its outer layer. Flag tests that reach into internals instead of exercising the public entry point.

### Tests shouldn't fake everything in reach.
Fake at the boundary, to trigger upstream conditions the test needs or to stand in for what's slow or unavailable. Ideally, the majority of parts inside the system under test should be real.

## Example output

```markdown
**Must**

- `Sources/Chat/Views/Conversation/FeedIntent.swift:5` — "Replaces the old item-diffing
  approach, which used to infer intent from list changes." Comments should describe the
  code as it is now. Cut to what the enum is for today.

- `src/eigin_relay/config/models.toml:34` — `glm-5.2` is an alias of `glm-5.3` here, but
  `docs/src/relay/models.md:12` calls it a separate option. Docs should only claim what's
  true and consistent with the change.

**Should**

- `Sources/Chat/Views/Conversation/FeedScrollCoordinator.swift:101` — `resolveAppend` and
  `AppendOutcome` name the mechanism. Behaviourally these are "anchor a page" and "pin a
  new send".

**Consider**

- `Sources/Chat/Utilities/MessageWindow.swift:341` — six-line comment above a one-line
  guard. The second half restates the condition.
```

Nothing to flag is a normal result: say `LGTM — nothing to flag.` and stop.
