# Design system

Eigin uses a centralised design token system as the single source of truth for visual primitives: colours, spacing, typography, and layout. Changing a token and running `make generate` propagates the change through all generated platform code.

## Design tokens

Tokens are defined in `design/tokens.json` using the [W3C Design Tokens Community Group format](https://design-tokens.github.io/community-group/format/). The file is human-readable, not tied to any one platform, and structured in two layers:

**Palette** — color primitives without no semantic meaning. Referenced by the `color` group.

**Semantic tokens** — named by purpose. Many have a `$value` (light mode) and a `$modes.dark` override (dark mode). Aliases use the `{group.key}` syntax.

Token groups in `tokens.json`:

| Group | Contents |
|---|---|
| `palette` | Raw colour values: `neutral`, `brand`, `white`, `black`, `negative`, `warning`, `positive` |
| `color` | Semantic colours: nested groups for `surface`, `text`, `border`, `button`, `icon`, `input`, `accent` |
| `typography` | 20 type styles with `fontSize`, `lineHeight`, `letterSpacing`, `fontWeight`, `fontFamily` |
| `fontFamily` | Font family definitions: `display` (NorthEastCN) and `ui` (FiveSerifText) |
| `letterSpacing` | Named letter-spacing scale referenced by typography tokens |
| `spacing` | Numeric spacing scale: `n2` through `n128` |
| `radius` | Corner radius values: `card` (24 px), `full` (pill) |
| `strokeWeight` | Border/stroke widths: `standard` (3 px) |
| `grid` | Layout grid per breakpoint (mobile/tablet/desktop): columns, outer margin, inner padding, gutter |

When adding a token to any group that has a corresponding `*_FIELDS` constant in `tools/src/design/ios/style.rs` (currently `SPACING_FIELDS` and `TYPOGRAPHY_FIELDS`), add the key there too — tokens absent from the list are skipped by codegen.

## Assets

### Fonts

Font files (OTF/TTF) placed in `design/assets/fonts/` are picked up at generation time, registered with the app via CoreText, and copied into `Resources/Fonts/`. If the folder is empty, the app falls back to platform system fonts. Proprietary fonts are not committed to the repository; add them locally to activate them.

### App icon

The source icon lives in `design/assets/icon/`. Generation copies it into the iOS asset catalogue. For development builds, a `dev_overlay.png` is composited on top so dev and production installs are visually distinct. The current icon is a placeholder.

## Code generation

Running `make generate` reads the token file and assets, then produces platform-native code. For iOS, the following files are written to `Sources/Core/Design/Generated/` (git-ignored, so machine-local font choices don't pollute source control):

| File | Contents |
|---|---|
| `ResolvedColors.swift` | Nested structs mirroring the `color` token tree |
| `DefaultTheme.swift` | Light and dark colour values resolved from tokens |
| `Spacing.swift` | Spacing scale as `CGFloat` constants |
| `Typography.swift` | Typography scale as `TypographyStyle` values |
| `Radius.swift` | Corner radius scale as `CGFloat` constants |
| `StrokeWeight.swift` | Stroke/border width scale as `CGFloat` constants |
| `Grid.swift` | Layout grid breakpoints as `Grid.Breakpoint` values |
| `FontRegistration.swift` | Registers custom fonts with CoreText at launch |
| `Color+Hex.swift` | `Color(hex:)` initialiser used by the theme |

## Usage in SwiftUI

```swift
@Environment(\.colors) private var colors

// Colours — nested by purpose
Text("Hello").foregroundStyle(colors.text.standard.primary)
view.background(colors.surface.standard.base)
view.overlay(RoundedRectangle(cornerRadius: Radius.card)
    .stroke(colors.border.standard.base, lineWidth: StrokeWeight.standard))

// Typography
Text("Hello").typography(Typography.body)
Text("LABEL").typography(Typography.miniLabel)  // uppercase applied by style

// Spacing
VStack(spacing: Spacing.n16) { ... }
    .padding(.horizontal, Spacing.n24)

// Grid — use Grid.compact / Grid.regular / Grid.wide directly,
// or inject the active breakpoint via environment when responsive layout is needed
view.padding(.horizontal, Grid.compact.outer)
```

The colour token tree mirrors the `color` group structure in `tokens.json`. Navigate it by purpose: `colors.surface.*`, `colors.text.*`, `colors.border.*`, `colors.icon.*`, etc.
