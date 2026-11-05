import Foundation

/// Private native Mistral content retained for continuation with its original destination.
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

/// Collects streamed native content; only completed responses become replayable history.
struct MistralReasoningAccumulator: ReasoningCapturing {
    let origin: ReasoningOrigin
    private var parts: [MistralContentPart] = []
    private var valid = true

    init(origin: ReasoningOrigin) {
        self.origin = origin
    }

    mutating func invalidate() {
        valid = false
    }

    mutating func append(chunk: Data) {
        do {
            guard let root = try JSONSerialization.jsonObject(with: chunk) as? [String: Any],
                  let choices = root["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"], !(content is NSNull)
            else { return }
            if let text = content as? String {
                append([.text(text)], plainText: true)
            } else {
                let data = try JSONSerialization.data(withJSONObject: content)
                try append(JSONDecoder().decode([MistralContentPart].self, from: data))
            }
        } catch {
            invalidate()
        }
    }

    mutating func append(_ deltas: [MistralContentPart], plainText: Bool = false) {
        for part in deltas {
            guard part.type == "text" || part.type == "thinking" else {
                valid = false
                continue
            }
            if part.type == "thinking",
               part.thinking?.contains(where: { $0.type != "text" }) == true
            {
                valid = false
            }
            // Only an explicitly open thinking block establishes continuation across chunks.
            if parts.last?.type == "thinking", parts.last?.closed == false {
                guard part.type == "thinking" else {
                    valid = false
                    continue
                }
                let index = parts.count - 1
                parts[index].thinking = (parts[index].thinking ?? []) + (part.thinking ?? [])
                if let closed = part.closed { parts[index].closed = closed }
                if let signature = part.signature {
                    if let previous = parts[index].signature,
                       previous != signature { valid = false }
                    parts[index].signature = signature
                }
            } else if plainText, part.type == "text", parts.last?.type == "text" {
                parts[parts.count - 1].text = (parts.last?.text ?? "") + (part.text ?? "")
            } else {
                parts.append(part)
            }
        }
    }

    func completed() -> ReasoningHistory? {
        guard valid,
              parts.contains(where: { $0.type == "thinking" }),
              !parts.contains(where: { $0.closed == false }) else { return nil }
        return try? MistralReasoningHistory(origin: origin, parts: parts).stored()
    }
}
