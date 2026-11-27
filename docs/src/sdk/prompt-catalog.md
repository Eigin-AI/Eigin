# Prompt catalog

Use Eigin's bundled prompts or supply your own catalog. Conversation APIs also
accept finished prompt strings directly.

## Bundled prompts

Swift hosts get typed accessors from the SDK package:

```swift
let text = EiginSDK.DefaultPrompts.Hints.space(
    name: "Research", instructions: "Keep notes concise."
)
```

Other hosts use `PromptCatalog.defaultCatalog().render(name, parameters)` with a
catalog-relative name such as `hints/space.jinja`. Apple integration prompts live
under `platforms/apple/`; select prompts that match your host's capabilities.

Native catalog operations are synchronous and require no SDK initialization.
Browser hosts first await `initialize()` to load WASM. The default catalog is
embedded and shared; rendering needs no files or network access.

## Your own catalog

Supply a JSON string with exactly two required fields: `schema_version` must be
`1`, and `templates` maps unique, nonempty names to template strings. Unknown
fields are rejected.

```json
{
  "schema_version": 1,
  "templates": { "greeting": "Hello {{ name }}!" }
}
```

```swift
let catalog = try EiginSDK.PromptCatalog.fromJson(document: document)
try catalog.validateUsages(usages: ["greeting": ["name"]])
let text = try catalog.render(name: "greeting", parameters: ["name": "Ada"])
```

Custom catalogs are independent. Supported syntax:

- `{{ name }}` inserts a string verbatim.
- `{% if name %}…{% else %}…{% endif %}` tests whether a string is nonempty.
- `{% include "name" %}` inserts another template from this catalog.
- `{# comment #}` removes a comment.

Conditional nesting and include chains are limited to 64 levels.

Loading validates the document and all includes. Rendering requires exactly the
resolved string parameters, including those in unselected branches. Use
`validateUsages` at startup or in tests to check the names and parameter sets your
host expects before a conversation needs them.

Errors distinguish `InvalidCatalog`, `UnknownTemplate`, `InvalidParameters`, and
`InvalidUsages`. Diagnostics explain each failure; their message wording may
change. Browser bindings use `Map` for parameters/usages; Rust uses `HashMap` and
snake_case method names.
