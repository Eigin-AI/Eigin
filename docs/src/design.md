# Design system

Eigin uses a centralised design token system as the single source of truth for visual primitives: colours, spacing, and typography. Changing a token and running `make generate` propagates the change through all generated platform code. The full Eigin design is still being developed — token values will be revisited when it arrives.

## Design tokens

Tokens are defined in `design/tokens.json` using the [W3C Design Tokens Community Group format](https://design-tokens.github.io/community-group/format/). This format is human-readable, machine-readable, and supported (or planned) by design tools including Figma — which should eventually allow direct export into this format.

The token file lives at the repo root and is not tied to any one platform. Token groups: `color`, `spacing`, `typography`, `fontFamily`.

## Assets

### Fonts

Font files (OTF/TTF) placed in `design/assets/fonts/` are picked up at generation time, registered with the app via CoreText, and copied into `Resources/Fonts/`. If the folder is empty, the app falls back to platform system fonts. Proprietary fonts are not committed to the repository; add them locally to activate them. Open-source alternatives are planned for a future pass.

### App icon

The source icon lives in `design/assets/icon/`. Generation copies it into the iOS asset catalogue. For development builds, a `dev_overlay.png` is composited on top so dev and production installs are visually distinct. The current icon is a placeholder — not the final design.

## Code generation

Running `make generate` reads the token file and assets, then produces platform-native code. For iOS, the following files are written to `Sources/Core/Design/Generated/` (git-ignored, so machine-local font choices don't pollute source control):

| File | Contents |
|---|---|
| `DefaultTheme.swift` | Light and dark colour values resolved from tokens |
| `Spacing.swift` | Spacing scale as `CGFloat` constants |
| `Typography.swift` | Typography scale as `TypographyStyle` values |
| `FontRegistration.swift` | Registers custom fonts with CoreText at launch |
| `Color+Hex.swift` | `Color(hex:)` initialiser used by the theme |

Use the generated namespaces directly in SwiftUI views:

```swift
@Environment(\.colors) private var colors

// Colours
Text("Hello").foregroundStyle(colors.textPrimary)
view.background(colors.surface)

// Typography
Text("Hello").typography(Typography.body)
Text("Label").typography(Typography.label)

// Spacing
VStack(spacing: Spacing.md) { ... }
    .padding(Spacing.lg)
```

The principle: **sans-serif** (`subheadline`, `label`, `caption`, `headline`) for UI chrome — buttons, row titles, navigation. **Serif** (`body`, `callout`) for readable content — message text, previews, prose.
