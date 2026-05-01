import Foundation

/// Enriched metadata for a single LLM model, including pricing, capability flags, and context
/// limits.
/// Populated by ``ModelMetadataService`` using data from the models.dev registry.
struct ModelMetadata: Identifiable {
    let id: String
    var name: String
    /// Optional suffix extracted from the model ID (e.g. `"20251001"`, `"2025-04-14"`).
    /// Useful for distinguishing multiple IDs that resolve to the same display name.
    var versionTag: String?
    var isKnown: Bool
    var supportsChat: Bool
    var contextWindow: Int?
    var maxOutput: Int?
    var inputCostPerMillion: Double?
    var outputCostPerMillion: Double?
    var supportsReasoning: Bool
    var supportsToolCall: Bool
    var supportsVision: Bool
}
