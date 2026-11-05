import Foundation

/// Private continuation state carried unchanged between compatible requests.
struct ReasoningHistory: Codable, Equatable, Sendable {
    let origin: ReasoningOrigin
    let format: String
    let payload: Data
    let visibleText: String
    let additionalInputTokens: Int

    func matches(_ message: ChatMessage, origin: ReasoningOrigin?) -> Bool {
        self.origin == origin && message.role == "assistant"
            && visibleText == (message.content ?? "")
    }
}

/// Identifies the provider configuration, endpoint, and model that produced reasoning.
struct ReasoningOrigin: Codable, Equatable, Sendable {
    let providerID: UUID
    let endpoint: String
    let model: String

    static func destination(providerID: UUID?, baseURL: String, model: String) -> Self? {
        guard let providerID else { return nil }
        let endpoint = ProviderPreset.isRelay(baseURL)
            ? RelayConfiguration.baseURL?.appendingPathComponent("v1").absoluteString ?? baseURL
            : baseURL
        guard var components = URLComponents(string: endpoint) else { return nil }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.host = components.host?.lowercased()
        components.scheme = components.scheme?.lowercased()
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return Self(providerID: providerID, endpoint: components.string ?? endpoint, model: model)
    }
}

extension ChatMessage {
    /// Returns a request-only copy with reasoning scoped to the destination.
    func reasoningScoped(to origin: ReasoningOrigin?) -> ChatMessage {
        var copy = self
        if reasoningHistory?.matches(self, origin: origin) != true {
            copy.reasoningHistory = nil
        }
        return copy
    }
}
