@testable import Eigin
import Foundation
import Testing

@Suite("ChatMessage Coding")
struct ChatMessageCodingTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Test func encodesAndDecodesWithToolCalls() throws {
        let toolCalls = [
            ToolCall(
                id: "call_1",
                type: "function",
                function: .init(name: "read_core", arguments: "{\"core\":\"identity\"}")
            ),
        ]
        let message = ChatMessage(role: "assistant", content: "Let me check.", toolCalls: toolCalls)

        let data = try encoder.encode(message)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        #expect(decoded.role == "assistant")
        #expect(decoded.content == "Let me check.")
        #expect(decoded.toolCalls?.count == 1)
        #expect(decoded.toolCalls?.first?.id == "call_1")
        #expect(decoded.toolCalls?.first?.function.name == "read_core")
    }

    @Test func encodesAndDecodesToolRoleWithToolCallID() throws {
        let message = ChatMessage(
            role: "tool",
            content: "{\"result\":\"OK\"}",
            toolCallID: "call_1"
        )

        let data = try encoder.encode(message)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        #expect(decoded.role == "tool")
        #expect(decoded.toolCallID == "call_1")
        #expect(decoded.content == "{\"result\":\"OK\"}")
    }

    @Test func omitsNilOptionalFieldsFromJSON() throws {
        let message = ChatMessage(role: "user", content: "Hello")
        let data = try encoder.encode(message)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["role"] as? String == "user")
        #expect(json["content"] as? String == "Hello")
        #expect(json["tool_call_id"] == nil)
        #expect(json["tool_calls"] == nil)
    }

    @Test func decodesContentAsNilWhenAbsent() throws {
        let json = Data("{\"role\":\"assistant\"}".utf8)
        let decoded = try decoder.decode(ChatMessage.self, from: json)

        #expect(decoded.role == "assistant")
        #expect(decoded.content == nil)
        #expect(decoded.toolCallID == nil)
        #expect(decoded.toolCalls == nil)
    }
}
