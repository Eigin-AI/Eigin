import Foundation

/// Enriches raw model IDs with metadata (names, context windows, pricing, capabilities).
protocol ModelMetadataService: Sendable {
    /// Looks up each model ID in the catalog and returns ``ModelMetadata`` for recognised models.
    /// Unknown models are omitted from the result.
    func enrich(modelIDs: [String], provider: String) async -> [ModelMetadata]
}

/// Implementation that resolves model IDs against ``KnownModelCatalog``.
struct CatalogModelMetadataService: ModelMetadataService {
    func enrich(modelIDs: [String], provider: String) async -> [ModelMetadata] {
        modelIDs.compactMap { id in
            guard let entry = KnownModelCatalog.lookup(id) else { return nil }
            return ModelMetadata(
                id: id,
                name: entry.displayName,
                versionTag: KnownModelCatalog.versionTag(for: id),
                isKnown: true,
                supportsChat: true,
                contextWindow: entry.contextWindow,
                maxOutput: entry.maxOutput,
                inputCostPerMillion: entry.inputCostPerMillion,
                outputCostPerMillion: entry.outputCostPerMillion,
                supportsReasoning: entry.supportsReasoning,
                supportsToolCall: entry.supportsToolCall,
                supportsVision: entry.supportsVision
            )
        }
    }
}
