# Prompts

Source-controlled templates for Eigin's agent prompts. The text lives here so it
is easy to read, review, and iterate on, instead of being buried in Swift string
literals.

At `just generate`, `eigin-tools` compiles every `*.jinja` file in this tree into
typed Swift accessors at `src/eigin_ios/Sources/Core/Design/Generated/Prompt.swift`.
There is **no runtime template engine** — prompts are plain Swift constants and
functions.

## How it maps to Swift

The folder tree becomes nested enums under `Prompt`, and each file becomes a leaf:

| Template | Generated symbol |
| --- | --- |
| `system/small.jinja` (no variables) | `Prompt.System.small` — `static let` |
| `system/main.jinja` (has variables) | `Prompt.System.main(name:…)` — `static func` |
| `system/partials/preamble.jinja` | `Prompt.System.Partials.preamble(name:…)` |

- A template with no variables compiles to a `static let` constant.
- A template with `{{ variables }}` compiles to a `static func` taking one
  `String` parameter per variable.

## Top-level prompts vs partials

A prompt family has one or more **callable** prompts (what the app renders, e.g.
`main`, `small`) and may have **partials** — fragments meant only to be
`{% include %}`d by others (e.g. `preamble`, `behavioral`). Put partials in a
`partials/` subfolder so both the file tree and the generated API
(`Prompt.<Family>.Partials.*`) make the distinction clear. Callable prompts sit
at the family root and are named by role (`main`, `small`, `initiative`, …).

## Supported syntax

Templates own prose, conditionals, and composition. Everything else — formatting,
selecting variants, iterating lists — is computed in Swift and passed in as
`String` values.

- `{{ name }}` — substitutes a `String`. Variables are plain identifiers; no
  attribute access (`{{ a.b }}`), filters, or operators.
- `{% if name %}…{% else %}…{% endif %}` — emits the branch based on whether the
  `String` is non-empty.
- `{% include "rel/path.jinja" %}` — composes another template at build time. The
  included template's parameters are forwarded automatically. Paths are relative
  to this directory.

Loops (`{% for %}`), `{% set %}`, macros, and filters are **rejected** at
`just generate` time. When a prompt needs a loop (e.g. a list of intents), the
Swift caller iterates and renders each item through a small per-item template.

## Adding a prompt

1. Add a `*.jinja` file under the right folder (create folders to group related
   prompts — they become nested enums).
2. Use `{{ variables }}` for values the Swift caller provides.
3. Run `just generate` and call the new `Prompt.<Folder>.<name>` symbol from Swift.

Keep byte-stable prompts (anything injected at the start of a cached chat turn)
free of per-turn data — that belongs in the `<system_hint>` block assembled by the
`Gatekeeper`, not here.
