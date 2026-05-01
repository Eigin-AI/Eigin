# Localization

All user-facing text lives in `Sources/Localizable.xcstrings` and is accessed through the generated `Localized` enum. This lets the app switch language at runtime via `Bundle.appLanguage` rather than being tied to the system locale.

## How it works

1. **String catalog** (`Localizable.xcstrings`) holds keys and their translations.
2. **Generated enum** (`Sources/Core/Localized.swift`) provides type-safe access. Run `make generate` to regenerate it after catalog changes.
3. **Usage in code** — always use the enum, never raw strings:

   ```swift
   // Good: Type safe
   Text(Localized.Ui.Tabs.chats)

   // Bad: Hard to track
   Text("Chats")
   ```

4. **Key convention** — dot-separated, leaf in `camelCase`, segments in `PascalCase` in the enum:

   | Catalog key | Swift access |
   |-------------|--------------|
   | `ui.tabs.chats` | `Localized.Ui.Tabs.chats` |
   | `chat.emptyState.title` | `Localized.Chat.EmptyState.title` |
   | `permission.deny` | `Localized.Permission.deny` |

## Adding a new string

1. Open `Sources/Localizable.xcstrings` and add the key with English (and ideally other) translations.
2. Run `make generate` — this regenerates `Localized.swift` with the new enum member.
3. Use the new member in code.

## What not to do

- **Don't use `String(localized:)` or `Text("")` with hardcoded English**
- **Don't use flat keys** like `"Error"` or `"👋"` — the generator skips keys without dots
- **Don't edit `Localized.swift` by hand** — it's overwritten on every `make generate`.
