# Design system

Eigin uses a centralised design token system as the single source of truth for visual primitives. Changing a token and running `just generate` propagates the change through all generated platform code.

## Design tokens

Tokens are defined in `design/tokens.json` using the [W3C Design Tokens Community Group format](https://design-tokens.github.io/community-group/format/). The file is structured in two layers:

**Palette** - raw colour primitives with no semantic meaning, referenced by the semantic layer.

**Semantic tokens** - named by purpose. Most provide both a light mode value and a dark mode override. Token groups cover colours, typography, spacing, layout, radius, and stroke weights. Layout tokens provide different values per breakpoint (mobile, tablet, desktop).

## Assets

Assets live in `design/assets/` and are picked up at generation time. This includes fonts, icons, and the app icon. Fonts and icons are copied into platform resources and registered automatically. Proprietary fonts are not committed to the repository - add them locally to activate them.

## Code generation

Running `just generate` reads the token file and assets, then produces platform-native styling code. For iOS, generated files are written to `Sources/Core/Design/Generated/` and cover colours, typography, spacing, layout, radius, stroke weights, font registration, and typed icon accessors.

Generated files are git-ignored so machine-local font choices don't pollute source control.

## Design components

Eigin apps implement a design component library based on the Eigin design system. Components consume the generated tokens directly, so visual changes flow from tokens through to components without manual updates.
