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

    // MARK: - AnthropicAdapter

    @Test func anthropicAdapterInjectsCacheControl() throws {
        let adapter = AnthropicAdapter()
        let input = try JSONSerialization.data(withJSONObject: [
            "model": "anthropic/claude-sonnet-4-5",
            "messages": [["role": "user", "content": "hello"]],
        ] as [String: Any])

        let output = try adapter.processRequestBody(input, messages: [])
        let json = try JSONSerialization.jsonObject(with: output) as? [String: Any]

        let cacheControl = json?["cache_control"] as? [String: String]
        #expect(cacheControl == ["type": "ephemeral"])
        // Verify existing fields are preserved
        #expect(json?["model"] as? String == "anthropic/claude-sonnet-4-5")
    }

    @Test func anthropicAdapterDoesNotTreatStopAsToolCalls() {
        #expect(AnthropicAdapter().treatsStopAsToolCalls == false)
    }

    // MARK: - ProviderAdapterFactory

    @Test func factoryReturnsAnthropicAdapterForOpenRouterAnthropicModel() {
        let adapter = ProviderAdapterFactory.adapter(
            for: "https://openrouter.ai/api/v1",
            model: "claude-sonnet-4-5-20250514"
        )
        #expect(adapter is AnthropicAdapter)
    }

    @Test func factoryReturnsDefaultForOpenRouterNonAnthropicModel() {
        let adapter = ProviderAdapterFactory.adapter(
            for: "https://openrouter.ai/api/v1",
            model: "gpt-4o"
        )
        #expect(adapter is DefaultAdapter)
    }

    @Test func factoryReturnsDefaultForNonOpenRouterURL() {
        let adapter = ProviderAdapterFactory.adapter(
            for: "https://api.example.com/v1",
            model: "claude-sonnet-4-5-20250514"
        )
        #expect(adapter is DefaultAdapter)
    }
}
