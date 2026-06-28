import Foundation

/// Renders the user's preferred language so the model replies in kind.
@MainActor
final class LanguageSource: SystemHintSource {
    let title = "Language"

    func render(_ input: SystemHintInput) async -> String? {
        guard let language = input.language else { return nil }
        return Prompt.Hints.language(language: language.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
