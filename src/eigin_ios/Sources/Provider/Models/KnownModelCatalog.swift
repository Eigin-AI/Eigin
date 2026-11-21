import EiginSDK
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
    /// Approximate provider input price in USD per million tokens.
    let inputCostPerMillion: Double?
    /// Approximate provider output price in USD per million tokens, used for relative cost badges.
    let outputCostPerMillion: Double?
    let supportsToolCall: Bool
    let supportsReasoning: Bool
    let supportsVision: Bool
    let isRecommended: Bool
    let reasoningControl: ReasoningControl?

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
        isRecommended: Bool,
        reasoningControl: ReasoningControl? = nil
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
        self.reasoningControl = reasoningControl
    }
}

/// App type adaptation for the SDK-owned curated catalog.
enum KnownModelCatalog {
    private typealias Catalog = EiginSDK.ModelCatalog
    static let entries = Catalog.entries.map(KnownModelEntry.init)
    static let preferenceRanking = Catalog.preferenceRanking
    static let costTerciles = Catalog.costTerciles

    static func lookup(_ modelID: String) -> KnownModelEntry? {
        Catalog.lookup(modelID).map { KnownModelEntry($0.entry) }
    }

    static func versionTag(for modelID: String) -> String? {
        Catalog.lookup(modelID)?.versionTag
    }

    static func bestModel(from available: [String]) -> String? {
        Catalog.bestModel(from: available)
    }

    static func knownModels(in available: [String]) -> [String] {
        Catalog.knownModels(in: available)
    }

    static func rank(of model: String) -> Int {
        Catalog.preferenceRank(model) ?? .max
    }
}

private extension KnownModelEntry {
    init(_ entry: EiginSDK.ModelCatalog.Entry) {
        self.init(
            pattern: entry.pattern, aliases: entry.aliases, displayName: entry.displayName,
            family: ModelFamily(entry.family), contextWindow: Int(clamping: entry.contextWindow),
            maxOutput: entry.maxOutput.map { Int(clamping: $0) },
            inputCostPerMillion: entry.inputCostPerMillion,
            outputCostPerMillion: entry.outputCostPerMillion,
            supportsToolCall: entry.supportsToolCall, supportsReasoning: entry.supportsReasoning,
            supportsVision: entry.supportsVision, isRecommended: entry.isRecommended,
            reasoningControl: entry.reasoningControl.map(ReasoningControl.init)
        )
    }
}

private extension ModelFamily {
    init(_ family: EiginSDK.ModelCatalog.Family) {
        switch family {
        case .openAi: self = .openai
        case .anthropic: self = .anthropic
        case .google: self = .google
        case .mistral: self = .mistral
        case .grok: self = .grok
        case .zhipu: self = .zhipu
        case .moonshot: self = .moonshot
        case .alibaba: self = .alibaba
        case .minimax: self = .minimax
        case .deepseek: self = .deepseek
        case .apple: self = .apple
        case .gemma: self = .gemma
        case .nvidia: self = .nvidia
        case .corti: self = .corti
        }
    }
}
