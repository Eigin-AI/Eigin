# Names and versioning

## Names

Products have two names: a public one for marketing, and an internal code name we build under. Our code names come from birds, because birds fly free. 

The public Eigin app for personal use is `Finch`.

Bundle identifiers use reverse domain form with the code name: `ai.eigin.<name>`. For Finch that is `ai.eigin.finch`. Development and staging builds add a `.dev` suffix: `ai.eigin.finch.dev`.

We use code names for identifiers instead of the marketing name so we can rename, reposition or expand a product without touching identifiers, entitlements, or store records.

## Versioning

Eigin has one primary **product version** and one independent **SDK version**.
Both live in `[version]` in `config/app.toml`.

| Component | Version |
| --- | --- |
| Shipped apps, app extensions, relay, CLI | Product version |
| SDK library and language bindings | SDK version |
| SDK test host, internal tools, website, design packages | Build/commit identity; no managed release version |

### Compatibility

Use numeric `MAJOR.MINOR.PATCH` versions following semantic versioning.
Before SDK 1.0, breaking API changes bump its minor version; document migration steps.

The relay API (`/v1`) has its own compatibility contract. Keep older apps working
across relay deployments.

Schemas, migrations, export formats, signed agreements, assets, and build numbers
keep their own versions. Fastlane manages iOS build numbers.

### Releases

We aim for one product release every 2–4 weeks, with urgent patches as needed.
Use the release workflow in our pi extension:

1. Review changes and agree the product and SDK bumps.
2. Update `[version]` in `config/app.toml`; run `just generate` and review the diff.
3. Run `just version check` and relevant tests.
4. Draft release notes with git-cliff, review them, and follow the workflow to publish.

Generation synchronizes versions for app and SDK targets; docs generation is independent.
CI checks for drift. `just version show` displays both versions; `just version sync`
updates version metadata alone.

### Changelog

Keep one `CHANGELOG.md`, drafted with git-cliff and reviewed during the pi release
workflow. Each product release records its SDK version and changes by affected surface,
including SDK migration notes. Label SDK-only releases explicitly. Product tags use
numeric versions without a `v` prefix.
