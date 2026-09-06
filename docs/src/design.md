# Design system

The `design/` folder is the single source of truth for content generated into the Eigin apps. Edit a source, run `just generate`, and it flows into platform-native code.

| Folder | Generates |
|---|---|
| `tokens.json` | Design tokens: colour, type, spacing, layout, radius, strokes |
| `assets/` | Fonts, icons, app icon |
| `prompts/` | Agent prompt templates and skill flows |
| `knowledge/` | Bundled read-only knowledge about Eigin |
| `web/` | Svelte component library and gallery (see [Web](#web)) |

## Design tokens

`design/tokens.json`, in the [W3C Design Tokens format](https://design-tokens.github.io/community-group/format/), in two layers:

- **Palette**: raw colour primitives, referenced by the semantic layer.
- **Semantic tokens**: named by purpose, most with light and dark values. Cover colour, typography, spacing, layout, radius, and strokes. Layout tokens vary per breakpoint (mobile, tablet, desktop).

## Assets

`design/assets/` holds fonts, icons, and the app icon. They're copied into platform resources and registered automatically at generation time. Proprietary fonts aren't committed: add them locally to activate them.

## Prompts

`design/prompts/` holds agent prompt text as Jinja templates, mirrored by folder into typed accessors: `prompts/skills/planning/instruction.jinja` becomes `Prompt.Skills.Planning.instruction`. A skill folder can also carry a `flows.toml` describing its flows (see [Skills](./agents/skills.md#flows)), compiled into a generated flow registry.

## Knowledge

`design/knowledge/` is the read-only knowledge that ships with the app: the Firm schema (`schemas.firm`) plus one seed entity per file about Eigin. It's a real [Firm](https://github.com/42futures/firm) workspace, so entries can be authored and validated with Firm tooling. See [Knowledge](./agents/knowledge.md#bundled-knowledge).

## Code generation

`just generate` reads everything under `design/` and writes typed accessors into each app's generated sources, so tokens, prompts, and knowledge are used through the type system rather than by raw string or path. Generated files are git-ignored, so machine-local font choices stay out of source control.

For the web, generation emits CSS custom properties (`tokens.css`, `typography.css`), the font files, and typed companions: `tokens.ts` (token values for styles that need them in TypeScript) and `icons.ts` (every icon as an SVG string).

## Design components

Eigin apps build a component library on the tokens. Components consume generated tokens directly, so a token change flows straight through without manual edits.

## Web

`design/web/` is a Svelte 5 + TypeScript component library built on the tokens, and the gallery is where you inspect and iterate on the UI system.

```
just run web        # gallery on localhost:5173
just test web       # svelte-check, Vite build, class-reference check
```

Browse components and screens in the sidebar. Screens are sketches of layout intent, not pixel traces — each holds exactly the content the real app has, in a device frame with real chrome. To add one: create it in `design/web/src/gallery/screens/`, register it in that folder's `index.ts`, and open it from the Screens list.
