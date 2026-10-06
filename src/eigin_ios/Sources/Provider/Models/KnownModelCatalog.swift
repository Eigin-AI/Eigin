import Foundation

/// Broad model family used to select provider-specific adapters when the
/// provider URL alone is not enough (e.g. models accessed via a router).
enum ModelFamily: String {
    case openai, anthropic, google, mistral, grok, zhipu, moonshot, alibaba, minimax, deepseek,
         apple, gemma, nvidia, corti
}

/// Metadata for a model family in the curated catalog.
struct KnownModelEntry {
    let pattern: String
    /// Alternate ID spellings that resolve to this same entry (e.g. a provider's
    /// variant of the canonical ID). Matched with the same rules as `pattern`.
    let aliases: [String]
    let displayName: String
    let family: ModelFamily
    let contextWindow: Int
    let maxOutput: Int?
    let inputCostPerMillion: Double?
    let outputCostPerMillion: Double?
    let supportsToolCall: Bool
    let supportsReasoning: Bool
    let supportsVision: Bool
    let isRecommended: Bool

    init(
        pattern: String,
        aliases: [String] = [],
        displayName: String,
        family: ModelFamily,
        contextWindow: Int,
        maxOutput: Int?,
        inputCostPerMillion: Double?,
        outputCostPerMillion: Double?,
        supportsToolCall: Bool,
        supportsReasoning: Bool,
        supportsVision: Bool,
        isRecommended: Bool
    ) {
        self.pattern = pattern
        self.aliases = aliases
        self.displayName = displayName
        self.family = family
        self.contextWindow = contextWindow
        self.maxOutput = maxOutput
        self.inputCostPerMillion = inputCostPerMillion
        self.outputCostPerMillion = outputCostPerMillion
        self.supportsToolCall = supportsToolCall
        self.supportsReasoning = supportsReasoning
        self.supportsVision = supportsVision
        self.isRecommended = isRecommended
    }
}

/// Curated catalog of models verified to work well with the app.
///
/// Each entry uses prefix matching to recognise model IDs across providers.
/// Entries are ordered most-specific first so `"gpt-4o-mini"` is checked before `"gpt-4o"`.
/// Use ``lookup(_:)`` to resolve an arbitrary model ID to its catalog entry.
enum KnownModelCatalog {
    /// Tercile boundaries for output cost across all priced catalog entries.
    /// Models at or below `lower` are `$`, above `upper` are `$$$`, between is `$$`.
    static let costTerciles: (lower: Double, upper: Double) = {
        let prices = entries.compactMap(\.outputCostPerMillion).sorted()
        guard prices.count >= 3 else { return (1.0, 15.0) }
        let lower = prices[(prices.count - 1) / 3]
        let upper = prices[(prices.count - 1) * 2 / 3]
        return (lower, upper)
    }()

    /// Returns the catalog entry matching `modelID`, or `nil` if unknown.
    static func lookup(_ modelID: String) -> KnownModelEntry? {
        preparedLookup(modelID)?.entry
    }

    /// One string a lookup can match against: an entry's `pattern` or one of
    /// its aliases, with its normalized form kept beside the original.
    private struct NormalizedCandidate {
        /// The candidate as written (the `pattern` or an alias), so matched
        /// length math stays on the same form the caller sees.
        let raw: String
        let normalized: String
        let entry: KnownModelEntry
    }

    /// Normalization allocates (lowercase, replaces, suffix trims), and model
    /// lists run into the hundreds, so the catalogue's candidates are
    /// normalized once instead of on every lookup. Order matches the naive
    /// scan: each entry's pattern comes before its aliases, entries in
    /// catalogue order.
    private static let normalizedCandidates: [NormalizedCandidate] = entries.flatMap { entry in
        ([entry.pattern] + entry.aliases).map {
            NormalizedCandidate(raw: $0, normalized: normalize($0), entry: entry)
        }
    }

    private static func preparedLookup(
        _ modelID: String
    ) -> (entry: KnownModelEntry, matched: String)? {
        let bare = normalize(stripPrefix(modelID))
        for candidate in normalizedCandidates
            where matchesPattern(bare, pattern: candidate.normalized)
        {
            return (candidate.entry, candidate.raw)
        }
        return nil
    }

    /// Resolves `modelID` against an arbitrary entry list, returning the matched
    /// entry and the specific string (pattern or alias) that matched.
    /// Callers use ``lookup(_:)``; this seam exists so tests can supply fixtures.
    static func lookup(
        _ modelID: String,
        in entries: [KnownModelEntry]
    ) -> (entry: KnownModelEntry, matched: String)? {
        let bare = normalize(stripPrefix(modelID))
        for entry in entries {
            for candidate in [entry.pattern] + entry.aliases
                where matchesPattern(bare, pattern: normalize(candidate))
            {
                return (entry, candidate)
            }
        }
        return nil
    }

    /// Extracts a version tag from the suffix of a model ID (e.g. `"20251001"` from
    /// `"claude-haiku-4-5-20251001"`, or `"2025-04-14"` from `"gpt-4.1-2025-04-14"`).
    /// Returns `nil` if the model is unknown or the ID has no suffix beyond the pattern.
    static func versionTag(for modelID: String) -> String? {
        let bare = normalize(stripPrefix(modelID))
        guard let match = preparedLookup(modelID) else { return nil }
        let matchedLength = normalize(match.matched).count
        guard bare.count > matchedLength else { return nil }
        let suffix = bare[bare.index(bare.startIndex, offsetBy: matchedLength)...]
        let tag = String(suffix.drop(while: { $0 == "-" || $0 == "@" || $0 == ":" }))
        return tag.isEmpty ? nil : tag
    }

    /// Version-tag extraction against an arbitrary entry list. Chops the ID by the
    /// length of whichever string matched (pattern or alias), not always `pattern`.
    static func versionTag(for modelID: String, in entries: [KnownModelEntry]) -> String? {
        let bare = normalize(stripPrefix(modelID))
        guard let match = lookup(modelID, in: entries) else { return nil }
        let matchedLength = normalize(match.matched).count
        guard bare.count > matchedLength else { return nil }
        let suffix = bare[bare.index(bare.startIndex, offsetBy: matchedLength)...]
        let tag = String(suffix.drop(while: { $0 == "-" || $0 == "@" || $0 == ":" }))
        return tag.isEmpty ? nil : tag
    }

    // MARK: - Model Selection

    /// Global model preference ranking, best-first.
    /// Walk this list top-to-bottom and pick the first pattern that matches
    /// a model in the provider's available models.
    static let preferenceRanking: [String] = [
        // Top tier — best cost-quality balance for personal assistants
        // Corti models lead: fastest good answers for everyday personal use.
        "corti-s1",
        "corti-s1-instant",
        "corti-s1-mini",
        "corti-s1-mini-instant",
        "claude-sonnet-5",
        "claude-sonnet-4-6",
        "gpt-6.1",
        "gpt-6.1-astra",
        "gpt-6-astra",
        "gpt-5.6",
        "gpt-5.6-terra",
        "glm-5.3",
        "glm-5.2",
        "gpt-5.5",
        "mistral-medium-latest",
        "mistral-medium-2508",
        "gemini-3.5-flash",
        "gpt-5.4",
        "gemini-3.1-pro-preview",
        "gemini-3-pro-preview",
        "gpt-4.1",
        "mistral-medium-2604",
        "mistral-large-latest",
        "mistral-large-2512",
        "kimi-k3",
        "glm-5.3-flash",
        "minimax-m3",
        "gpt-5.4-mini",
        "gpt-4.1-mini",
        "gpt-4.1-nano",
        "kimi-k2.7-code",
        "kimi-k2.6",
        "kimi-k2.5",
        "kimi-k2",
        // Mid-tier — solid performers from all families
        "gemini-2.5-pro",
        "gemini-3.1-flash-lite",
        "gemini-3-flash-preview",
        "gemini-2.5-flash",
        "grok-4.3",
        "grok-4-fast",
        "mistral-small-latest",
        "mistral-small-2506",
        "mistral-small-2603",
        "claude-sonnet-4-5",
        "claude-haiku-4-5",
        "grok-4",
        "glm-5-turbo",
        "glm-5v-turbo",
        "glm-5.1",
        "qwen3.7-max",
        "qwen3.7-plus",
        "gpt-6.1-luna",
        "gpt-6.1-sol",
        "gpt-5.4-nano",
        "gpt-5.6-luna",
        "gpt-5.6-sol",
        "nvidia-nemotron-3-super-120b-a12b",
        "gemma-4-31b-it",
        "deepseek-v4-pro",
        "deepseek-v4-flash",
        "grok-3",
        "grok-3-mini",
        "qwen3-235b-a22b-thinking-2507",
        "qwen3-235b-a22b-instruct-2507",
        "glm-5",
        "glm-4.7",
        "glm-4.6",
        "minimax-m2.7",
        "minimax-m2.5",
        "minimax-m2.1",
        "minimax-m2",
        "deepseek-v3-1-terminus",
        "deepseek-v3.2",
        // Extreme cost / flagship tier
        "gpt-5.5-pro",
        "claude-opus-4-8",
        "claude-fable-5",
        "claude-opus-4-7",
        "claude-opus-4-6",
        "claude-opus-4-5",
        "gpt-5.5-instant",
        "gpt-5.2-pro",
        "gpt-5.2",
        "gpt-5.1",
        // Local models (always last)
        "apple-foundation-model",
        "gemma-4-e2b",
    ]

    /// Returns the best model from `available` according to the preference ranking,
    /// or the first catalog-known model, or the first available model as fallback.
    static func bestModel(from available: [String]) -> String? {
        bestModel(from: available, ranking: preferenceRanking, in: entries)
    }

    /// The models in `available` the catalog recognises. What gets enabled when a
    /// provider is seeded: unknown IDs are left off and explained on the models
    /// screen until the user opts them in.
    static func knownModels(in available: [String]) -> [String] {
        available.filter { lookup($0) != nil }
    }

    /// Selection core with injectable ranking and catalog, mirroring the `lookup(_:in:)`
    /// seam, so tests exercise the selection behavior rather than the current ranking.
    static func bestModel(
        from available: [String],
        ranking: [String],
        in entries: [KnownModelEntry]
    ) -> String? {
        for pattern in ranking {
            let normalizedPattern = normalize(pattern)
            if let match = available.first(where: {
                matchesPattern(normalize(stripPrefix($0)), pattern: normalizedPattern)
            }) {
                return match
            }
        }
        return available.first { lookup($0, in: entries) != nil } ?? available.first
    }

    // MARK: - Pattern Matching

    /// Strips vendor (`openai/`) or platform (`models/`) prefixes from a model ID.
    private static func stripPrefix(_ modelID: String) -> String {
        guard let slashIndex = modelID.firstIndex(of: "/") else { return modelID }
        return String(modelID[modelID.index(after: slashIndex)...])
    }

    /// Normalizes a model ID by lowercasing, replacing `.` with `-`, and stripping
    /// quantization suffixes so that IDs like `GLM-4.7-FP8` match pattern `glm-4-7`.
    private static func normalize(_ id: String) -> String {
        var result = id.lowercased().replacingOccurrences(of: ".", with: "-")
        for suffix in ["-fp8", "-fp16", "-bf16", "-int8", "-int4", "-awq", "-gptq", "-gguf"] {
            if result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
                break
            }
        }
        return result
    }

    /// Returns `true` if `id` matches `pattern` as a prefix, allowing version suffixes
    /// (digits or `-`/`@`/`:` followed by a digit) but not variant names (letters like `-mini`).
    private static func matchesPattern(_ id: String, pattern: String) -> Bool {
        guard id.hasPrefix(pattern) else { return false }
        if id.count == pattern.count { return true }

        let suffix = id[id.index(id.startIndex, offsetBy: pattern.count)...]
        guard let first = suffix.first else { return true }

        if first == "-" || first == ":" || first == "@" {
            guard let second = suffix.dropFirst().first else { return false }
            return second.isNumber
        }

        return first.isNumber
    }

    // MARK: - Catalog

    /// All known model entries, ordered most-specific first within each prefix group.
    /// Lookup uses first-match, so a shorter pattern (e.g. `kimi-k2`) will swallow a
    /// longer sibling (`kimi-k2.5`) if it appears earlier — always place the longer
    /// pattern first.
    static let entries: [KnownModelEntry] = [
        // OpenAI
        // SIWC (ChatGPT subscription) family — letter-suffixed slugs that the
        // pattern matcher won't reach from the base pattern alone.
        // `gpt-6-astra` listed live on an eligible account.
        KnownModelEntry(
            pattern: "gpt-6-astra",
            displayName: "GPT-6 Astra",
            family: .openai,
            contextWindow: 1_050_000,
            maxOutput: 128_000,
            inputCostPerMillion: 2.50,
            outputCostPerMillion: 15.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "gpt-6.1-astra",
            displayName: "GPT-6.1 Astra",
            family: .openai,
            contextWindow: 1_050_000,
            maxOutput: 128_000,
            inputCostPerMillion: 2.50,
            outputCostPerMillion: 15.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "gpt-6.1-sol",
            displayName: "GPT-6.1 Sol",
            family: .openai,
            contextWindow: 1_050_000,
            maxOutput: 128_000,
            inputCostPerMillion: 5.00,
            outputCostPerMillion: 30.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gpt-6.1-luna",
            displayName: "GPT-6.1 Luna",
            family: .openai,
            contextWindow: 1_050_000,
            maxOutput: 128_000,
            inputCostPerMillion: 1.00,
            outputCostPerMillion: 6.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gpt-6.1",
            displayName: "GPT-6.1",
            family: .openai,
            contextWindow: 1_050_000,
            maxOutput: 128_000,
            inputCostPerMillion: 5.00,
            outputCostPerMillion: 30.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "gpt-5.6",
            displayName: "GPT-5.6",
            family: .openai,
            contextWindow: 1_050_000,
            maxOutput: 128_000,
            inputCostPerMillion: 5.00,
            outputCostPerMillion: 30.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "gpt-5.6-terra",
            displayName: "GPT-5.6 Terra",
            family: .openai,
            contextWindow: 1_050_000,
            maxOutput: 128_000,
            inputCostPerMillion: 2.50,
            outputCostPerMillion: 15.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "gpt-5.6-luna",
            displayName: "GPT-5.6 Luna",
            family: .openai,
            contextWindow: 1_050_000,
            maxOutput: 128_000,
            inputCostPerMillion: 1.00,
            outputCostPerMillion: 6.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gpt-5.6-sol",
            displayName: "GPT-5.6 Sol",
            family: .openai,
            contextWindow: 1_050_000,
            maxOutput: 128_000,
            inputCostPerMillion: 5.00,
            outputCostPerMillion: 30.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gpt-5.5-pro",
            displayName: "GPT-5.5 Pro",
            family: .openai,
            contextWindow: 1_050_000,
            maxOutput: 128_000,
            inputCostPerMillion: 27.27,
            outputCostPerMillion: 163.64,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gpt-5.5",
            displayName: "GPT-5.5",
            family: .openai,
            contextWindow: 1_050_000,
            maxOutput: 128_000,
            inputCostPerMillion: 3.00,
            outputCostPerMillion: 18.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "gpt-5.5-instant",
            displayName: "GPT-5.5 Instant",
            family: .openai,
            contextWindow: 400_000,
            maxOutput: 128_000,
            inputCostPerMillion: 5.00,
            outputCostPerMillion: 30.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gpt-5.4",
            displayName: "GPT-5.4",
            family: .openai,
            contextWindow: 1_050_000,
            maxOutput: 128_000,
            inputCostPerMillion: 2.50,
            outputCostPerMillion: 15.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "gpt-5.4-mini",
            displayName: "GPT-5.4 Mini",
            family: .openai,
            contextWindow: 400_000,
            maxOutput: 128_000,
            inputCostPerMillion: 0.68,
            outputCostPerMillion: 4.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gpt-5.4-nano",
            displayName: "GPT-5.4 Nano",
            family: .openai,
            contextWindow: 400_000,
            maxOutput: 128_000,
            inputCostPerMillion: 0.18,
            outputCostPerMillion: 1.10,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gpt-5.2-pro",
            displayName: "GPT-5.2 Pro",
            family: .openai,
            contextWindow: 400_000,
            maxOutput: 128_000,
            inputCostPerMillion: 51.00,
            outputCostPerMillion: 168.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gpt-5.2",
            displayName: "GPT-5.2",
            family: .openai,
            contextWindow: 400_000,
            maxOutput: 128_000,
            inputCostPerMillion: 1.75,
            outputCostPerMillion: 14.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "gpt-5.1",
            displayName: "GPT-5.1",
            family: .openai,
            contextWindow: 400_000,
            maxOutput: 128_000,
            inputCostPerMillion: 1.25,
            outputCostPerMillion: 10.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "gpt-4.1",
            displayName: "GPT-4.1",
            family: .openai,
            contextWindow: 1_047_576,
            maxOutput: 32768,
            inputCostPerMillion: 2.00,
            outputCostPerMillion: 8.00,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gpt-4.1-mini",
            displayName: "GPT-4.1 Mini",
            family: .openai,
            contextWindow: 1_047_576,
            maxOutput: 32768,
            inputCostPerMillion: 0.40,
            outputCostPerMillion: 1.60,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gpt-4.1-nano",
            displayName: "GPT-4.1 Nano",
            family: .openai,
            contextWindow: 1_047_576,
            maxOutput: 32768,
            inputCostPerMillion: 0.10,
            outputCostPerMillion: 0.40,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: true,
            isRecommended: false
        ),

        // Anthropic
        KnownModelEntry(
            pattern: "claude-sonnet-5",
            displayName: "Claude Sonnet 5",
            family: .anthropic,
            contextWindow: 1_000_000,
            maxOutput: 128_000,
            inputCostPerMillion: 2.00,
            outputCostPerMillion: 10.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "claude-fable-5",
            displayName: "Claude Fable 5",
            family: .anthropic,
            contextWindow: 1_000_000,
            maxOutput: 128_000,
            inputCostPerMillion: 10.00,
            outputCostPerMillion: 50.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "claude-opus-4-8",
            displayName: "Claude Opus 4.8",
            family: .anthropic,
            contextWindow: 1_000_000,
            maxOutput: 128_000,
            inputCostPerMillion: 4.29,
            outputCostPerMillion: 21.46,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "claude-opus-4-7",
            displayName: "Claude Opus 4.7",
            family: .anthropic,
            contextWindow: 1_000_000,
            maxOutput: 128_000,
            inputCostPerMillion: 4.50,
            outputCostPerMillion: 22.50,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "claude-opus-4-6",
            displayName: "Claude Opus 4.6",
            family: .anthropic,
            contextWindow: 200_000,
            maxOutput: 128_000,
            inputCostPerMillion: 5.00,
            outputCostPerMillion: 25.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "claude-opus-4-5",
            displayName: "Claude Opus 4.5",
            family: .anthropic,
            contextWindow: 200_000,
            maxOutput: 64000,
            inputCostPerMillion: 5.00,
            outputCostPerMillion: 25.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "claude-sonnet-4-6",
            displayName: "Claude Sonnet 4.6",
            family: .anthropic,
            contextWindow: 200_000,
            maxOutput: 64000,
            inputCostPerMillion: 3.00,
            outputCostPerMillion: 15.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "claude-sonnet-4-5",
            displayName: "Claude Sonnet 4.5",
            family: .anthropic,
            contextWindow: 200_000,
            maxOutput: 64000,
            inputCostPerMillion: 3.00,
            outputCostPerMillion: 15.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "claude-haiku-4-5",
            displayName: "Claude Haiku 4.5",
            family: .anthropic,
            contextWindow: 200_000,
            maxOutput: 64000,
            inputCostPerMillion: 1.00,
            outputCostPerMillion: 5.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),

        // Google
        KnownModelEntry(
            pattern: "gemini-3.5-flash",
            displayName: "Gemini 3.5 Flash",
            family: .google,
            contextWindow: 1_048_576,
            maxOutput: 65536,
            inputCostPerMillion: 1.50,
            outputCostPerMillion: 9.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "gemini-3.1-pro-preview",
            displayName: "Gemini 3.1 Pro Preview",
            family: .google,
            contextWindow: 1_048_576,
            maxOutput: 65536,
            inputCostPerMillion: 2.00,
            outputCostPerMillion: 12.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "gemini-3.1-flash-lite",
            displayName: "Gemini 3.1 Flash Lite",
            family: .google,
            contextWindow: 1_048_576,
            maxOutput: 65536,
            inputCostPerMillion: 0.25,
            outputCostPerMillion: 1.50,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gemini-3-pro-preview",
            displayName: "Gemini 3 Pro Preview",
            family: .google,
            contextWindow: 1_000_000,
            maxOutput: 64000,
            inputCostPerMillion: 2.00,
            outputCostPerMillion: 12.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gemini-3-flash-preview",
            displayName: "Gemini 3 Flash Preview",
            family: .google,
            contextWindow: 1_048_576,
            maxOutput: 65536,
            inputCostPerMillion: 0.50,
            outputCostPerMillion: 3.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro",
            family: .google,
            contextWindow: 1_048_576,
            maxOutput: 65536,
            inputCostPerMillion: 1.25,
            outputCostPerMillion: 10.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "gemini-2.5-flash",
            displayName: "Gemini 2.5 Flash",
            family: .google,
            contextWindow: 1_048_576,
            maxOutput: 65536,
            inputCostPerMillion: 0.30,
            outputCostPerMillion: 2.50,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),

        // Mistral
        KnownModelEntry(
            pattern: "mistral-large-latest",
            displayName: "Mistral Large (latest)",
            family: .mistral,
            contextWindow: 262_144,
            maxOutput: 262_144,
            inputCostPerMillion: 0.50,
            outputCostPerMillion: 1.50,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "mistral-large-2512",
            aliases: ["mistral-large-3"],
            displayName: "Mistral Large 3",
            family: .mistral,
            contextWindow: 262_144,
            maxOutput: 262_144,
            inputCostPerMillion: 0.50,
            outputCostPerMillion: 1.50,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "mistral-medium-latest",
            displayName: "Mistral Medium (latest)",
            family: .mistral,
            contextWindow: 262_144,
            maxOutput: 262_144,
            inputCostPerMillion: 0.40,
            outputCostPerMillion: 2.00,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "mistral-medium-2604",
            // Canonical Mistral ID plus Berget's variant spelling.
            aliases: ["mistral-medium-3-5", "Mistral-Medium-3.5-128B"],
            displayName: "Mistral Medium 3.5",
            family: .mistral,
            contextWindow: 262_144,
            maxOutput: 262_144,
            inputCostPerMillion: 1.50,
            outputCostPerMillion: 7.50,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "mistral-medium-2508",
            aliases: ["mistral-medium-3"],
            displayName: "Mistral Medium 3",
            family: .mistral,
            contextWindow: 262_144,
            maxOutput: 262_144,
            inputCostPerMillion: 0.40,
            outputCostPerMillion: 2.00,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "mistral-small-latest",
            displayName: "Mistral Small (latest)",
            family: .mistral,
            contextWindow: 128_000,
            maxOutput: 16384,
            inputCostPerMillion: 0.10,
            outputCostPerMillion: 0.30,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "mistral-small-2603",
            aliases: ["mistral-small-4"],
            displayName: "Mistral Small 4",
            family: .mistral,
            contextWindow: 256_000,
            maxOutput: 256_000,
            inputCostPerMillion: 0.15,
            outputCostPerMillion: 0.60,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "mistral-small-2506",
            aliases: ["mistral-small-3-1"],
            displayName: "Mistral Small 3.1",
            family: .mistral,
            contextWindow: 128_000,
            maxOutput: 16384,
            inputCostPerMillion: 0.10,
            outputCostPerMillion: 0.30,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: true,
            isRecommended: false
        ),

        // Grok
        KnownModelEntry(
            pattern: "grok-4.3",
            displayName: "Grok 4.3",
            family: .grok,
            contextWindow: 1_000_000,
            maxOutput: 30000,
            inputCostPerMillion: 1.25,
            outputCostPerMillion: 2.50,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "grok-4-fast",
            displayName: "Grok 4 Fast",
            family: .grok,
            contextWindow: 2_000_000,
            maxOutput: 30000,
            inputCostPerMillion: 0.2,
            outputCostPerMillion: 0.5,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "grok-4",
            displayName: "Grok 4",
            family: .grok,
            contextWindow: 256_000,
            maxOutput: 64000,
            inputCostPerMillion: 3.0,
            outputCostPerMillion: 15.0,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "grok-3",
            displayName: "Grok 3",
            family: .grok,
            contextWindow: 131_072,
            maxOutput: 8192,
            inputCostPerMillion: 3.0,
            outputCostPerMillion: 15.0,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: false,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "grok-3-mini",
            displayName: "Grok 3 Mini",
            family: .grok,
            contextWindow: 131_072,
            maxOutput: 8192,
            inputCostPerMillion: 0.3,
            outputCostPerMillion: 0.5,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: false
        ),

        // Zhipu (GLM)
        KnownModelEntry(
            pattern: "glm-5.3-flash",
            displayName: "GLM 5.3 Flash",
            family: .zhipu,
            contextWindow: 1_048_576,
            maxOutput: 131_072,
            // z.ai list prices; a 50% launch promo runs until Sep 2026.
            inputCostPerMillion: 0.15,
            outputCostPerMillion: 0.50,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "glm-5.3",
            displayName: "GLM 5.3",
            family: .zhipu,
            contextWindow: 1_048_576,
            maxOutput: 131_072,
            inputCostPerMillion: 1.40,
            outputCostPerMillion: 4.40,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "glm-5.2",
            displayName: "GLM 5.2",
            family: .zhipu,
            contextWindow: 1_000_000,
            maxOutput: 131_072,
            inputCostPerMillion: 1.40,
            outputCostPerMillion: 4.40,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "glm-5-turbo",
            displayName: "GLM-5 Turbo",
            family: .zhipu,
            contextWindow: 200_000,
            maxOutput: 131_072,
            inputCostPerMillion: 1.20,
            outputCostPerMillion: 4.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "glm-5v-turbo",
            displayName: "GLM-5V Turbo",
            family: .zhipu,
            contextWindow: 200_000,
            maxOutput: 131_072,
            inputCostPerMillion: 1.20,
            outputCostPerMillion: 4.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "glm-5.1",
            displayName: "GLM 5.1",
            family: .zhipu,
            contextWindow: 200_000,
            maxOutput: 131_072,
            inputCostPerMillion: 0.72,
            outputCostPerMillion: 2.30,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "glm-5",
            displayName: "GLM-5",
            family: .zhipu,
            contextWindow: 80000,
            maxOutput: 131_072,
            inputCostPerMillion: 0.72,
            outputCostPerMillion: 2.30,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "glm-4.7",
            displayName: "GLM 4.7",
            family: .zhipu,
            contextWindow: 204_800,
            maxOutput: 131_072,
            inputCostPerMillion: 0.6,
            outputCostPerMillion: 2.2,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "glm-4.6",
            displayName: "GLM 4.6",
            family: .zhipu,
            contextWindow: 200_000,
            maxOutput: 128_000,
            inputCostPerMillion: 0.6,
            outputCostPerMillion: 2.2,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: false
        ),

        // Kimi
        KnownModelEntry(
            pattern: "kimi-k3",
            displayName: "Kimi K3",
            family: .moonshot,
            contextWindow: 1_048_576,
            maxOutput: 131_072,
            inputCostPerMillion: 3.00,
            outputCostPerMillion: 15.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "kimi-k2.7-code",
            displayName: "Kimi K2.7 Code",
            family: .moonshot,
            contextWindow: 262_144,
            maxOutput: 262_144,
            inputCostPerMillion: 0.95,
            outputCostPerMillion: 4.00,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "kimi-k2.6",
            displayName: "Kimi K2.6",
            family: .moonshot,
            contextWindow: 262_144,
            maxOutput: 262_144,
            inputCostPerMillion: 0.83,
            outputCostPerMillion: 3.85,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "kimi-k2.5",
            displayName: "Kimi K2.5",
            family: .moonshot,
            contextWindow: 262_144,
            maxOutput: 262_144,
            inputCostPerMillion: 0.6,
            outputCostPerMillion: 3.0,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "kimi-k2",
            displayName: "Kimi K2",
            family: .moonshot,
            contextWindow: 131_072,
            maxOutput: 32768,
            inputCostPerMillion: 0.55,
            outputCostPerMillion: 2.2,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: false,
            isRecommended: false
        ),

        // Qwen
        KnownModelEntry(
            pattern: "qwen3.7-max",
            displayName: "Qwen 3.7 Max",
            family: .alibaba,
            contextWindow: 1_000_000,
            maxOutput: 65536,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "qwen3.7-plus",
            displayName: "Qwen 3.7 Plus",
            family: .alibaba,
            contextWindow: 1_000_000,
            maxOutput: 65536,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "qwen3-235b-a22b-thinking-2507",
            displayName: "Qwen 3 235B Thinking",
            family: .alibaba,
            contextWindow: 256_000,
            maxOutput: 32000,
            inputCostPerMillion: 0.65,
            outputCostPerMillion: 3.0,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "qwen3-235b-a22b-instruct-2507",
            displayName: "Qwen 3 235B Instruct",
            family: .alibaba,
            contextWindow: 256_000,
            maxOutput: 32000,
            inputCostPerMillion: 0.2,
            outputCostPerMillion: 0.6,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: false,
            isRecommended: false
        ),

        // MiniMax
        KnownModelEntry(
            pattern: "minimax-m3",
            displayName: "MiniMax M3",
            family: .minimax,
            contextWindow: 512_000,
            maxOutput: 128_000,
            inputCostPerMillion: 0.30,
            outputCostPerMillion: 1.20,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "minimax-m2.7",
            displayName: "MiniMax M2.7",
            family: .minimax,
            contextWindow: 204_800,
            maxOutput: 131_072,
            inputCostPerMillion: 0.30,
            outputCostPerMillion: 1.20,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "minimax-m2.5",
            displayName: "MiniMax M2.5",
            family: .minimax,
            contextWindow: 204_800,
            maxOutput: 131_072,
            inputCostPerMillion: 0.3,
            outputCostPerMillion: 1.2,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "minimax-m2.1",
            displayName: "MiniMax M2.1",
            family: .minimax,
            contextWindow: 204_800,
            maxOutput: 131_072,
            inputCostPerMillion: 0.3,
            outputCostPerMillion: 1.2,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "minimax-m2",
            displayName: "MiniMax M2",
            family: .minimax,
            contextWindow: 196_600,
            maxOutput: 118_000,
            inputCostPerMillion: 0.28,
            outputCostPerMillion: 1.15,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: false
        ),

        // DeepSeek
        KnownModelEntry(
            pattern: "deepseek-v4-pro",
            displayName: "DeepSeek V4 Pro",
            family: .deepseek,
            contextWindow: 1_000_000,
            maxOutput: 384_000,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "deepseek-v4-flash",
            displayName: "DeepSeek V4 Flash",
            family: .deepseek,
            contextWindow: 1_000_000,
            maxOutput: 384_000,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "deepseek-v3-1-terminus",
            displayName: "DeepSeek V3.1 Terminus",
            family: .deepseek,
            contextWindow: 163_840,
            maxOutput: 64000,
            inputCostPerMillion: 0.21,
            outputCostPerMillion: 0.79,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "deepseek-v3.2",
            displayName: "DeepSeek V3.2",
            family: .deepseek,
            contextWindow: 128_000,
            maxOutput: 64000,
            inputCostPerMillion: 0.28,
            outputCostPerMillion: 0.40,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: false,
            isRecommended: false
        ),

        // Corti (EU-hosted; limits measured against the API, not documented)
        KnownModelEntry(
            pattern: "corti-s1-mini-instant",
            displayName: "Corti S1 Mini Instant",
            family: .corti,
            contextWindow: 262_144,
            maxOutput: nil,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: true,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "corti-s1-mini",
            displayName: "Corti S1 Mini",
            family: .corti,
            contextWindow: 262_144,
            maxOutput: nil,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "corti-s1-instant",
            displayName: "Corti S1 Instant",
            family: .corti,
            contextWindow: 262_144,
            maxOutput: nil,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: false,
            isRecommended: false
        ),
        KnownModelEntry(
            pattern: "corti-s1",
            displayName: "Corti S1",
            family: .corti,
            contextWindow: 262_144,
            maxOutput: nil,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: true
        ),

        // Apple
        KnownModelEntry(
            pattern: "apple-foundation-model",
            displayName: "Apple Foundation Model",
            family: .apple,
            contextWindow: 4096,
            maxOutput: 1024,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            supportsToolCall: true, // TODO: Test how reliable this is
            supportsReasoning: false,
            supportsVision: false,
            isRecommended: true
        ),

        // Gemma (LiteRT-LM / GPU)
        KnownModelEntry(
            pattern: "gemma-4-e2b",
            displayName: "Gemma 4 E2B",
            family: .gemma,
            contextWindow: 8192,
            maxOutput: 512,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            supportsToolCall: true,
            supportsReasoning: false,
            supportsVision: false, // Model supports this, can add later
            isRecommended: true
        ),
        KnownModelEntry(
            pattern: "gemma-4-31b-it",
            displayName: "Gemma 4 31B",
            family: .gemma,
            contextWindow: 128_000,
            maxOutput: 8192,
            inputCostPerMillion: 0.28,
            outputCostPerMillion: 0.55,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: true,
            isRecommended: true
        ),

        // NVIDIA (relay-hosted)
        KnownModelEntry(
            pattern: "nvidia-nemotron-3-super-120b-a12b",
            // Many providers drop the `nvidia-` prefix.
            aliases: ["nemotron-3-super-120b-a12b"],
            displayName: "Nemotron 3 Super 120B A12B",
            family: .nvidia,
            contextWindow: 262_144,
            maxOutput: 262_144,
            inputCostPerMillion: 0.20,
            outputCostPerMillion: 0.80,
            supportsToolCall: true,
            supportsReasoning: true,
            supportsVision: false,
            isRecommended: true
        ),
    ]
}
