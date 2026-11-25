@testable import Eigin
import EiginSDK

/// SDK lexical scoring and expected tiers for app recall tests.
enum KnowledgeLexicalMatcher {
    typealias SDK = EiginSDK.Experimental.Knowledge

    static let qualifiedIDScore = 2.2
    static let exactIDScore = 2.0
    static let exactNameScore = 1.8
    static let identityPhraseScore = 1.6
    static let fullCoverageScore = 1.2

    struct Query {
        let text: String
        init(_ text: String) {
            self.text = text
        }
    }

    static func score(entity: FirmEntity, qualifiedID: String, query: Query) -> Double {
        SDK.lexicalScore(
            entity: entity,
            qualifiedID: qualifiedID,
            query: query.text
        )
    }
}
