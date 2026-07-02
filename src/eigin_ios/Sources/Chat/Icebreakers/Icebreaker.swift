import Foundation

/// A short piece of text authored in both supported languages, resolved to the
/// app's current language at read time so it honors a live language switch.
struct LocalizedText: Sendable, Hashable {
    let en: String
    let da: String

    /// The value for the currently selected app language.
    var resolved: String {
        switch AppLanguage.current {
        case .english: en
        case .danish: da
        }
    }
}

/// A use-case group of icebreakers shown on an empty chat, declared in
/// `design/prompts/icebreakers/*.toml` and compiled into ``IcebreakerRegistry``.
struct IcebreakerGroup: Identifiable, Sendable, Hashable {
    let id: String
    /// The group's use-case label (e.g. "Get organized"), shown on the chip.
    let label: LocalizedText
    /// Whether this group is surfaced ahead of the others (e.g. for new capabilities).
    let featured: Bool
    /// Stable ordering among non-featured groups; lower comes first.
    let order: Int
    let icebreakers: [IcebreakerPrompt]
}

/// A single suggested opener within an ``IcebreakerGroup``.
struct IcebreakerPrompt: Identifiable, Sendable, Hashable {
    let id: String
    /// The short label shown in the expanded card row.
    let title: LocalizedText
    /// The full priming prompt placed into the composer when tapped.
    let prompt: LocalizedText
}
