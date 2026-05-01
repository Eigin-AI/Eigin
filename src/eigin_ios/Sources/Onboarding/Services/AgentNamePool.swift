import Foundation

/// Localized name suggestions for the agent-naming stage of onboarding.
///
/// The pool is keyed by ``AppLanguage`` so that names feel natural in the
/// user's language. Falls back to English when a language has no pool.
///
/// All names are short (1–2 syllables), pronounceable, and distinctive —
/// the kind of name you might give a personal assistant. Think Siri, Alexa,
/// but less common.
enum AgentNamePool {
    static let pool: [AppLanguage: [String]] = [
        .english: [
            "Ariel",
            "Brio",
            "Cael",
            "Coda",
            "Echo",
            "Elia",
            "Halo",
            "Haven",
            "Iris",
            "Juno",
            "Kira",
            "Lux",
            "Mira",
            "Nico",
            "Nova",
            "Onyx",
            "Opal",
            "Orion",
            "Pax",
            "Sage",
            "Sol",
            "Vale",
            "Vera",
        ],
        .danish: [
            "Aksel",
            "Bodil",
            "Egon",
            "Elise",
            "Freja",
            "Gry",
            "Iben",
            "Jens",
            "Kaja",
            "Knud",
            "Liv",
            "Mads",
            "Maren",
            "Nils",
            "Rune",
            "Signe",
            "Søren",
            "Tove",
            "Viggo",
        ],
    ]

    /// Returns `count` random name suggestions for the given language.
    /// Falls back to English when the language has no pool.
    static func suggestions(
        for language: AppLanguage,
        count: Int = 3
    ) -> [String] {
        let names = pool[language] ?? pool[.english] ?? []
        return Array(names.indices.shuffled().prefix(count)).map { names[$0] }
    }
}
