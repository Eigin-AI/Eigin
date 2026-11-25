import EiginSDK
import Foundation

// App-facing names for the experimental SDK values.
typealias FirmEntity = KnowledgeSDKConversion.SDK.Entity
typealias FirmField = KnowledgeSDKConversion.SDK.Field
typealias FirmFieldValue = KnowledgeSDKConversion.SDK.FieldValue
typealias FirmQueryResult = KnowledgeSDKConversion.SDK.QueryResult
typealias FirmDirection = KnowledgeSDKConversion.SDK.Direction
typealias FirmSchema = KnowledgeSDKConversion.SDK.Schema
typealias FirmSchemaField = KnowledgeSDKConversion.SDK.SchemaField

/// Maps host persistence and presentation values to SDK records.
enum KnowledgeSDKConversion {
    typealias SDK = EiginSDK.Experimental.Knowledge

    static func scoredEntity(_ result: SDK.SearchResult) -> KnowledgeSearchEngine
        .ScoredEntity
    {
        .init(
            entity: result.entity,
            qualifiedID: result.qualifiedId,
            score: result.score,
            relevance: result.relevance,
            chatID: result.chatId.flatMap(UUID.init(uuidString:))
        )
    }

    static func searchResult(_ result: KnowledgeSearchEngine.ScoredEntity) -> SDK
        .SearchResult
    {
        .init(
            entity: result.entity,
            qualifiedId: result.qualifiedID,
            sourceId: nil,
            chatId: result.chatID?.uuidString,
            relevance: result.relevance,
            score: result.score
        )
    }

    static func source(_ source: FirmSource) -> SDK.Source {
        .init(id: source.id.uuidString, path: source.path, content: source.content, readOnly: false)
    }
}
