import Foundation

/// Compatibility decoder for native Mistral history saved by earlier app builds.
struct MistralReasoningHistory: Codable, Equatable, Sendable {
    let origin: ReasoningOrigin
    var parts: [MistralContentPart]

    var thinkingText: String {
        parts.filter { $0.type == "thinking" }.flatMap { $0.thinking ?? [] }
            .compactMap(\.text).joined()
    }

    static let format = "mistral-content-v1"

    func stored() throws -> ReasoningHistory {
        try ReasoningHistory(
            origin: origin, format: Self.format,
            payload: JSONEncoder().encode(parts),
            visibleText: parts.filter { $0.type == "text" }.compactMap(\.text).joined(),
            additionalInputTokens: TokenEstimator.estimate(thinkingText) + parts.count * 4
        )
    }
}

/// Native Mistral text and nested thinking chunks, in their original order.
struct MistralContentPart: Codable, Equatable, Sendable {
    let type: String
    var text: String?
    var thinking: [MistralContentPart]?
    var closed: Bool?
    var signature: String?

    static func text(_ text: String) -> Self {
        Self(type: "text", text: text)
    }
}

extension ReasoningHistory {
    /// Reads current envelopes and native history saved by earlier development builds.
    static func decodeStored(_ data: Data) -> ReasoningHistory? {
        if let history = try? JSONDecoder()
            .decode(ReasoningHistory.self, from: data) { return history }
        return try? JSONDecoder().decode(MistralReasoningHistory.self, from: data).stored()
    }
}
