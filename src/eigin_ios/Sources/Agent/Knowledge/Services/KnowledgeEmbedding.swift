import EiginSDK

/// Selects portable embedding text; vector generation remains host-owned.
enum KnowledgeEmbedding {
    typealias SDK = EiginSDK.Experimental.Knowledge

    static func embeddingText(for entity: FirmEntity) -> String {
        SDK.embeddingText(entity)
    }
}
