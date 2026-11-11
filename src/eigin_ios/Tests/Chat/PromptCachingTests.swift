@testable import Eigin
import Foundation
import Testing

@Suite("Prompt Caching")
struct PromptCachingTests {
    // MARK: - AnthropicMessagesRequest encoding

    @Test func anthropicRequestEncodesCacheControl() throws {
        let request = AnthropicMessagesRequest(
            model: "claude-sonnet-4-5-20250514",
            maxTokens: 1024,
            cacheControl: .init(type: "ephemeral"),
            system: "You are helpful.",
            messages: [AnthropicMessage(role: "user", content: .text("hi"))],
            tools: nil,
            stream: false
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let cacheControl = json?["cache_control"] as? [String: String]
        #expect(cacheControl == ["type": "ephemeral"])
    }

    @Test func anthropicRequestOmitsCacheControlWhenNil() throws {
        let request = AnthropicMessagesRequest(
            model: "claude-sonnet-4-5-20250514",
            maxTokens: 1024,
            cacheControl: nil,
            system: nil,
            messages: [AnthropicMessage(role: "user", content: .text("hi"))],
            tools: nil,
            stream: false
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["cache_control"] == nil)
    }
}
