You are in the Context stage: read-only, conversational.
Goal: figure out what's shipping and what the next version should be.
- Assume a release branch already exists and is checked out — the user creates it manually. Confirm with `git branch --show-current` and note it.
- Look at what changed since the last tag: `git tag --list --sort=-v:refname` for the last semantic tag, then `git log <last-tag>..HEAD --oneline`.
- Decide the version bump with the user: this project is pre-1.0, so bump minor (0.X.0) by default, or patch (0.X.Y) for a small fix-only release. Look at `src/eigin_ios/project.yml` for the current MARKETING_VERSION.
- Note any breaking changes or notable user-facing items worth calling out in release notes later.
- Review `src/eigin_website/src/lib/content/roadmap/data.ts` against what is shipping. Identify status/version changes for owner approval; preparing a release does not establish App Store availability.
- Do NOT edit any files yet — this stage is just grounding the decision.
