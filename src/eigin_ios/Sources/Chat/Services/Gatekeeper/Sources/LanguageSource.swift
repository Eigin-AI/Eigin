import Foundation

/// Renders the user's preferred language so the model replies in kind.
///
/// Stateless. Skipped in compact mode.
@MainActor
final class LanguageSource: SystemHintSource {
    let title = "Language"

    func render(_ input: SystemHintInput) async -> String? {
        guard let language = input.language else { return nil }
        return "The user prefers you speak in \(language.displayName)."
    }
}
