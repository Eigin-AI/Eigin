# Naming products

Products have two names: a public one for marketing, and an internal code name we build under. Our code names come from birds, because birds fly free. 

The public Eigin app for personal use is `Finch`.

Bundle identifiers use reverse domain form with the code name: `ai.eigin.<name>`. For Finch that is `ai.eigin.finch`. Development and staging builds add a `.dev` suffix: `ai.eigin.finch.dev`.

We use code names for identifiers instead of the marketing name so we can rename, reposition or expand a product without touching identifiers, entitlements, or store records.
