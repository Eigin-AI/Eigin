import Foundation

/// Broad model family used to select provider-specific adapters when the
/// provider URL alone is not enough (e.g. models accessed via a router).
enum ModelFamily: String {
    case openai, anthropic, google, mistral, grok, zhipu, moonshot, alibaba, minimax, deepseek,
         apple, gemma
}

/// Metadata for a model family in the curated catalog.
struct KnownModelEntry {
    let pattern: String
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
        let bare = normalize(stripPrefix(modelID))
        return entries.first { matchesPattern(bare, pattern: normalize($0.pattern)) }
    }

    /// Extracts a version tag from the suffix of a model ID (e.g. `"20251001"` from
    /// `"claude-haiku-4-5-20251001"`, or `"2025-04-14"` from `"gpt-4.1-2025-04-14"`).
    /// Returns `nil` if the model is unknown or the ID has no suffix beyond the pattern.
    static func versionTag(for modelID: String) -> String? {
        let bare = normalize(stripPrefix(modelID))
        guard
            let entry = entries.first(where: {
                matchesPattern(bare, pattern: normalize($0.pattern))
            })
        else {
            return nil
        }
        let patternLength = normalize(entry.pattern).count
        guard bare.count > patternLength else { return nil }
        let suffix = bare[bare.index(bare.startIndex, offsetBy: patternLength)...]
        let tag = String(suffix.drop(while: { $0 == "-" || $0 == "@" || $0 == ":" }))
        return tag.isEmpty ? nil : tag
    }

    // MARK: - Model Selection

    /// Global model preference ranking, best-first.
    /// Walk this list top-to-bottom and pick the first pattern that matches
    /// a model in the provider's available models.
    static let preferenceRanking: [String] = [
        // Top tier — Western, curated, cost-efficient
        "claude-sonnet-4-6",
        "gpt-5.4",
        "gemini-3-pro-preview",
        "gpt-5.2",
        "gemini-3-flash-preview",
        "claude-sonnet-4-5",
        "gpt-5.1",
        "mistral-large-2512",
        "mistral-medium-2508",
        "gpt-4.1",
        // Mixed — best agentic performers from all families
        "kimi-k2.5",
        "gemini-2.5-pro",
        "minimax-m2.7",
        "gpt-4.1-mini",
        "gemini-2.5-flash",
        "grok-4",
        "grok-4-fast",
        "mistral-small-2506",
        "qwen3-235b-a22b-thinking-2507",
        "claude-haiku-4-5",
        "grok-3",
        "gpt-4.1-nano",
        "qwen3-235b-a22b-instruct-2507",
        "glm-4.7",
        "glm-5",
        "kimi-k2",
        "grok-3-mini",
        "glm-4.6",
        "minimax-m2.5",
        "deepseek-v3-1-terminus",
        "minimax-m2.1",
        "minimax-m2",
        // Extreme cost / flagship tier
        "claude-opus-4-6",
        "claude-opus-4-5",
        "gpt-5.2-pro",
        // Local models (always last)
        "apple-foundation-model",
        "gemma-4-e2b",
    ]

    /// Returns the best model from `available` according to the preference ranking,
    /// or the first catalog-known model, or the first available model as fallback.
    static func bestModel(from available: [String]) -> String? {
        for pattern in preferenceRanking {
            let normalizedPattern = normalize(pattern)
            if let match = available.first(where: {
                matchesPattern(normalize(stripPrefix($0)), pattern: normalizedPattern)
            }) {
                return match
            }
        }
        return available.first { lookup($0) != nil } ?? available.first
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

        // Anthropic
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
            isRecommended: true
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
            isRecommended: true
        ),

        // Mistral
        KnownModelEntry(
            pattern: "mistral-large-2512", // TODO: also sometimes known as mistral-large-3
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
            pattern: "mistral-medium-2508", // TODO: also sometimes known as mistral-medium-3
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
            pattern: "mistral-small-2506", // TODO: also sometimes known as mistral-small-3.1
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
            displayName: "Grok 4 Fast",
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

        // Z
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

        // Kimi
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

        // MiniMax
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

        // Gemma (CoreML/ANE)
        KnownModelEntry(
            pattern: "gemma-4-e2b",
            displayName: "Gemma 4 E2B",
            family: .gemma,
            contextWindow: 1024,
            maxOutput: 512,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            supportsToolCall: false, // Model supports this, but is unreliable
            supportsReasoning: false,
            supportsVision: false, // Model supports this, can add later
            isRecommended: true
        ),
    ]
}
