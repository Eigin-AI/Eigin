# Prompts

`*.jinja` files here define Eigin's default prompt catalog. The SDK embeds and
renders them. Swift hosts get typed accessors under `EiginSDK.DefaultPrompts`;
iOS uses the shorthand `Prompt`.

## Edit and generate

1. Add or edit a template in the relevant folder. Use `partials/` for included fragments.
2. Run `just generate sdk apple` or `just generate sdk web` to update the embedded catalog and bindings.
3. Use the generated Swift accessor or render by the template's relative path.

Folders become nested Swift enums; filenames become properties or functions:

| Template | Swift accessor |
| --- | --- |
| `hints/space.jinja` | `EiginSDK.DefaultPrompts.Hints.space(name:instructions:)` |
| `platforms/apple/tools/weather_attribution.jinja` | `EiginSDK.DefaultPrompts.Platforms.Apple.Tools.weatherAttribution` |

Templates without parameters become static properties. Others take string
arguments, including parameters required by their includes.

## Syntax

- `{{ name }}` inserts a string verbatim.
- `{% if name %}…{% else %}…{% endif %}` tests whether a string is nonempty.
- `{% include "relative/path.jinja" %}` includes another catalog template.
- `{# comment #}` removes a comment while preserving surrounding whitespace.

Parameters use bare identifiers. Hosts prepare lists and formatting before
rendering; loops, filters, and expressions are rejected during generation.

## Applicability

Keep Apple integration prompts under `platforms/apple/`. Hosts choose prompts
whose integrations and assumptions they support. Flow and localized icebreaker
registries remain app-owned.

See [Prompt catalog](../../docs/src/sdk/prompt-catalog.md) for custom catalogs and
runtime validation.
