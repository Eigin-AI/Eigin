import Foundation

/// Keyword tables behind `QueryComplexity`. Split out so adding a language or
/// signal never touches the scoring logic.
///
/// Deliberately not localized: these are recognition dictionaries, not UI
/// strings. Every table is matched against every message, so mixed-language
/// input (pasted English in a Danish chat, say) still scores correctly.
///
/// Markers that are prefixes of everyday dictation words ("let me", "weighted",
/// "rapidly") are deliberately absent — a false step-up there is expensive, not
/// harmless.
enum QueryComplexityMarkers {
    static let codeMarkers = [
        "```", "func ", "def ", "class ", "struct ", "enum ",
        "import ", "export ", "const ", "function ",
        "=>", "();", "await ", "async ", "SELECT ", "FROM ",
        " api ", "json", "http", "git ",
    ]

    static let reasoningMarkers = [
        // English
        "step by step", "think through", "think carefully", "analyze", "analyse",
        "figure out", "reason about",
        // Danish
        "trin for trin", "tænk igennem", "tænk grundigt", "analyser", "find ud af",
        "overvej nøje",
    ]

    static let technicalTerms = [
        // English
        "architecture", "distributed", "encryption", "database", "algorithm",
        "latency", "throughput", "concurrency", "protocol", "convention",
        "deployment", "kubernetes", "terraform", "compile", "regex",
        "oauth", "thread", "migration", "schema",
        // Work tools — the nouns of agentic requests.
        "gitlab", "github", "repo", "repository", "pull request",
        "merge request", "pipeline", "commit",
        // Danish
        "arkitektur", "distribueret", "kryptering", "database", "algoritme",
        "latenstid", "gennemstrømning", "samtidighed", "protokol", "konvention",
        "udrulning", "kompilere", "skema",
    ]

    static let multiStepPatterns = [
        // English — " step " catches "step one/step 1/…" without listing variants.
        "first of all", " then ", "after that", " step ", "1.", "2.", "3.",
        // Danish
        "for det første", " derefter ", " bagefter ", " trin ",
    ]

    static let simpleIndicators = [
        // English
        "what is", "what's", "who is", "when is", "where is",
        "hi", "hello", "hey", "thanks", "thank you",
        // Danish
        "hvad er", "hvem er", "hvornår er", "hvor er",
        "hej", "tak", "mange tak",
    ]
}
