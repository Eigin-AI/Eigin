@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Mistral reasoning replay", .serialized)
struct MistralReasoningReplayTests {
    private let model = "mistral-large-4-0"
    private let sse = [
        #"data: {"choices":[{"delta":{"content":[{"type":"thinking","thinking":[{"type":"text","text":"private "}],"closed":false}]}}]}"#,
        #"data: {"choices":[{"delta":{"content":[{"type":"thinking","thinking":[{"type":"text","text":"thought"}],"closed":true,"signature":"opaque-signature"},{"type":"thinking","thinking":[]},{"type":"text","text":"Answer"}]}}]}"#,
        #"data: {"choices":[{"delta":{"content":" continues"}}]}"#,
    ].joined(separator: "\n\n") + "\n\n"

    @Test(arguments: [false, true], [false, true])
    @MainActor func streamStoreReloadReplay(relay: Bool, toolRound: Bool) async throws {
        let base = relay ? "https://relay.test/v1" : "https://api.mistral.ai/v1"
        let url = base + "/chat/completions"
        let providerID = UUID()
        let client = OpenAICompatibleClient(
            baseURL: base, apiToken: "test", session: FakeURLProtocol.fakeSession(),
            providerID: providerID, isEiginRelay: relay
        )
        let ending = toolRound
            ? #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call00001","type":"function","function":{"name":"lookup","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}"#
            : #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        FakeURLProtocol.stubResponse(
            for: url,
            data: Data((sse + ending + "\n\n").utf8),
            statusCode: 200
        )
        let stream = try await client.chatCompletionEventStream(
            messages: [],
            model: model,
            tools: nil
        )
        var answer = ""
        var history: ReasoningHistory?
        var toolCalls: [ToolCall] = []
        for try await event in stream {
            if case .contentDelta(let text) = event { answer += text }
            if case .toolCall(let call) = event { toolCalls.append(call) }
            if case .reasoningHistory(let value) = event { history = value }
        }
        #expect(answer == "Answer continues")
        let capturedParts = try JSONDecoder().decode(
            [MistralContentPart].self,
            from: #require(history).payload
        )
        #expect(capturedParts.filter { $0.type == "thinking" }.flatMap { $0.thinking ?? [] }
            .compactMap(\.text).joined() == "private thought")
        let message = try ChatMessage(
            role: "assistant",
            content: answer,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
            reasoningHistory: #require(history)
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("store")
        do {
            let container = try ModelContainer(
                for: Schema(SchemaV12.models, version: SchemaV12.versionIdentifier),
                configurations: ModelConfiguration(url: storeURL)
            )
            container.mainContext.insert(Message.from(message))
            try container.mainContext.save()
        }
        let container = try ModelContainer(
            for: Schema(SchemaV12.models, version: SchemaV12.versionIdentifier),
            configurations: ModelConfiguration(url: storeURL)
        )
        let loaded = try #require(container.mainContext.fetch(FetchDescriptor<Message>()).first)
            .toChatMessage()
        #expect(loaded.reasoningHistory == history)
        #expect(try !String(decoding: JSONEncoder().encode(loaded), as: UTF8.self)
            .contains("opaque-signature"))
        FakeURLProtocol.stubResponse(for: url, data: Data("data: [DONE]\n\n".utf8), statusCode: 200)
        let next = try await client.chatCompletionEventStream(
            messages: [loaded],
            model: model,
            tools: nil
        )
        for try await _ in next {}
        let body = try #require(FakeURLProtocol.lastRequestBody(for: url))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect((messages.first?["tool_calls"] as? [[String: Any]])?.count == (toolRound ? 1 : nil))
        let parts = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(parts.map { $0["type"] as? String } == ["thinking", "thinking", "text"])
        #expect(parts.last?["text"] as? String == answer)
        #expect((parts.first?["thinking"] as? [[String: String]])?.compactMap { $0["text"] }
            .joined() == "private thought")
        #expect(parts.first?["signature"] as? String == "opaque-signature")
        #expect(parts.first?["closed"] as? Bool == true)

        for (id, endpoint, nextModel, isRelay) in [
            (UUID(), base, model, relay),
            (providerID, base, "mistral-small-2603", relay),
            (providerID, "https://openrouter.ai/api/v1", model, false),
            (providerID, "https://other-relay.test/v1", model, true),
        ] {
            let destination = OpenAICompatibleClient(
                baseURL: endpoint,
                apiToken: "test",
                session: FakeURLProtocol.fakeSession(),
                providerID: id,
                isEiginRelay: isRelay
            )
            let target = endpoint + "/chat/completions"
            FakeURLProtocol.stubResponse(
                for: target,
                data: Data("data: [DONE]\n\n".utf8),
                statusCode: 200
            )
            let switched = try await destination.chatCompletionEventStream(
                messages: [loaded],
                model: nextModel,
                tools: nil
            )
            for try await _ in switched {}
            let data = try #require(FakeURLProtocol.lastRequestBody(for: target))
            #expect(!String(decoding: data, as: UTF8.self).contains("opaque-signature"))
        }
        #expect(loaded.reasoningHistory == history)
    }

    @Test(arguments: ["", #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#])
    func incompleteResponsesNeverBecomeReplayable(ending: String) async throws {
        let url = "https://api.mistral.ai/v1/chat/completions"
        FakeURLProtocol.stubResponse(
            for: url,
            data: Data((sse + ending + "\n\n").utf8),
            statusCode: 200
        )
        let client = OpenAICompatibleClient(
            baseURL: "https://api.mistral.ai/v1",
            apiToken: "test",
            session: FakeURLProtocol.fakeSession(),
            providerID: UUID()
        )
        let stream = try await client.chatCompletionEventStream(
            messages: [],
            model: model,
            tools: nil
        )
        for try await event in stream {
            if case .reasoningHistory = event {
                Issue.record("Incomplete reasoning was retained")
            }
        }
    }

    @Test(arguments: [false, true])
    func omittedClosureStateRequiresAnExplicitClose(close: Bool) async throws {
        let url = "https://api.mistral.ai/v1/chat/completions"
        var chunks = [
            #"data: {"choices":[{"delta":{"content":[{"type":"thinking","thinking":[{"type":"text","text":"first"}],"closed":false}]}}]}"#,
            #"data: {"choices":[{"delta":{"content":[{"type":"thinking","thinking":[{"type":"text","text":" second"}]}]}}]}"#,
        ]
        if close {
            chunks
                .append(
                    #"data: {"choices":[{"delta":{"content":[{"type":"thinking","thinking":[{"type":"text","text":" third"}],"closed":true}]}}]}"#
                )
        }
        chunks.append(#"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
        FakeURLProtocol.stubResponse(
            for: url,
            data: Data((chunks.joined(separator: "\n\n") + "\n\n").utf8),
            statusCode: 200
        )
        let client = OpenAICompatibleClient(
            baseURL: "https://api.mistral.ai/v1",
            apiToken: "test",
            session: FakeURLProtocol.fakeSession(),
            providerID: UUID()
        )
        let stream = try await client.chatCompletionEventStream(
            messages: [],
            model: model,
            tools: nil
        )
        var history: ReasoningHistory?
        for try await event in stream {
            if case .reasoningHistory(let value) = event { history = value }
        }
        if close {
            let parts = try JSONDecoder().decode(
                [MistralContentPart].self,
                from: #require(history).payload
            )
            #expect(parts.count == 1)
            #expect(parts.first?.thinking?.compactMap(\.text).joined() == "first second third")
            #expect(parts.first?.closed == true)
        } else {
            #expect(history == nil)
        }
    }

    @Test(arguments: [false, true])
    @MainActor func storedHistoryReplayUsesAdapterFormat(legacy: Bool) async throws {
        let providerID = UUID()
        let origin = ReasoningOrigin(
            providerID: providerID,
            endpoint: "https://api.mistral.ai/v1",
            model: model
        )
        let native = MistralReasoningHistory(origin: origin, parts: [
            MistralContentPart(type: "thinking", thinking: [.text("hidden legacy trace")]),
            .text("Answer"),
        ])
        let message = Message(role: "assistant", content: "Answer")
        if legacy {
            message.reasoningHistoryData = try JSONEncoder().encode(native)
        } else {
            let history = try ReasoningHistory(
                origin: origin,
                format: "unsupported-format-v1",
                payload: JSONEncoder().encode(native.parts),
                visibleText: "Answer",
                additionalInputTokens: 10
            )
            message.reasoningHistoryData = try JSONEncoder().encode(history)
        }
        let url = origin.endpoint + "/chat/completions"
        FakeURLProtocol.stubResponse(for: url, data: Data("data: [DONE]\n\n".utf8), statusCode: 200)
        let client = OpenAICompatibleClient(
            baseURL: origin.endpoint,
            apiToken: "test",
            session: FakeURLProtocol.fakeSession(),
            providerID: providerID
        )
        let stream = try await client.chatCompletionEventStream(
            messages: [message.toChatMessage()],
            model: model,
            tools: nil
        )
        for try await _ in stream {}
        let body = try #require(FakeURLProtocol.lastRequestBody(for: url))
        #expect(String(decoding: body, as: UTF8.self).contains("hidden legacy trace") == legacy)
    }
}
