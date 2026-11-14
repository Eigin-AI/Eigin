@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("ChatTranscriptTools", .serialized)
@MainActor
struct ChatTranscriptToolsTests {
    private func store() throws -> (ModelContainer, Agent, Chat) {
        let container = try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Test", providerID: UUID(), model: "test-model")
        let chat = Chat(agentID: agent.id)
        container.mainContext.insert(agent)
        container.mainContext.insert(chat)
        return (container, agent, chat)
    }

    private func insert(
        _ text: String,
        chat: Chat,
        context: ModelContext,
        time: Double = 1,
        role: String = "user"
    ) -> Message {
        let message = Message(role: role, content: text)
        message.timestamp = Date(timeIntervalSince1970: time)
        message.chat = chat
        context.insert(message)
        return message
    }

    private func call(_ args: [String: Any]) throws -> ToolCall {
        let data = try JSONSerialization.data(withJSONObject: args)
        return ToolCall(
            id: "test",
            type: "function",
            function: .init(name: "test", arguments: String(decoding: data, as: UTF8.self))
        )
    }

    private func result(_ output: ToolResult) throws -> [String: Any] {
        #expect(!output.isError, "\(output.content)")
        let json = try #require(try JSONSerialization
            .jsonObject(with: Data(output.content.utf8)) as? [String: Any])
        return try #require(json["result"] as? [String: Any])
    }

    @Test func searchesOlderTextAndRetrievesAnchorWithLimitOne() async throws {
        let (container, agent, chat) = try store()
        let older = insert(
            "We chose BLUE for the launch",
            chat: chat,
            context: container.mainContext
        )
        for i in 2 ... 30 {
            _ = insert(
                "Later message \(i)",
                chat: chat,
                context: container.mainContext,
                time: Double(i)
            )
        }
        _ = insert("BLUE tool payload", chat: chat, context: container.mainContext, role: "tool")
        try container.mainContext.save()
        let search = SearchChatTranscriptTool(currentChatID: chat.id)
        let found = try await result(search.execute(
            call(["query": "blue", "limit": 1]),
            agent: agent
        ))
        let hits = try #require(found["hits"] as? [[String: Any]])
        #expect(hits.count == 1)
        #expect(hits.first?["message_id"] as? String == older.id.uuidString)
        let read = GetChatTranscriptTool(currentChatID: chat.id)
        let page = try await result(read.execute(
            call(["around_message_id": older.id.uuidString, "limit": 1]),
            agent: agent
        ))
        #expect((page["transcript"] as? String)?.contains("BLUE") == true)
    }

    @Test func equalTimestampPaginationDoesNotSkipOrRepeatMessages() async throws {
        let (container, agent, chat) = try store()
        for i in 0 ..< 7 {
            _ = insert("Entry \(i)", chat: chat, context: container.mainContext)
        }
        try container.mainContext.save()
        let read = GetChatTranscriptTool(currentChatID: chat.id)
        var ids: [String] = []
        var args: [String: Any] = ["limit": 2]
        for _ in 0 ..< 5 {
            let page = try await result(read.execute(call(args), agent: agent))
            let entries = try #require(page["messages"] as? [[String: Any]])
            ids += entries.compactMap { $0["message_id"] as? String }
            guard let cursor = page["next_before_message_id"] as? String else { break }
            args["before_message_id"] = cursor
        }
        #expect(ids.count == 7)
        #expect(Set(ids).count == 7)
    }

    @Test func longMessagesAreBoundedAndFullyRecoverable() async throws {
        let (container, agent, chat) = try store()
        let text = String(repeating: "\"\\\n👨‍👩‍👧‍👦", count: 1600)
        let message = insert(text, chat: chat, context: container.mainContext)
        _ = insert(
            String(repeating: "new", count: 4000),
            chat: chat,
            context: container.mainContext,
            time: 2
        )
        try container.mainContext.save()
        let tool = GetChatTranscriptTool(currentChatID: chat.id)
        let around = try await result(tool.execute(
            call(["around_message_id": message.id.uuidString]),
            agent: agent
        ))
        #expect((around["messages"] as? [[String: Any]])?
            .contains { $0["message_id"] as? String == message.id.uuidString } == true)
        var recovered = ""
        var offset = 0
        for _ in 0 ..< 100 {
            let output = try await tool.execute(
                call(["read_message_id": message.id.uuidString, "content_offset": offset]),
                agent: agent
            )
            #expect(output.content.utf8.count <= 10000)
            let chunk = try result(output)
            recovered += try #require(chunk["content"] as? String)
            guard let next = chunk["next_content_offset"] as? Int else { break }
            #expect(next > offset)
            offset = next
        }
        #expect(recovered == text)
    }

    @Test func rejectsForeignChatCursorAndInvalidLimits() async throws {
        let (container, agent, chat) = try store()
        let foreign = Chat(agentID: UUID(), spaceID: UUID())
        container.mainContext.insert(foreign)
        let foreignMessage = insert("private", chat: foreign, context: container.mainContext)
        let scoped = GetChatTranscriptTool(spaceID: UUID(), currentChatID: chat.id)
        #expect(try await scoped.execute(call([:]), agent: agent).isError)
        let tool = GetChatTranscriptTool(currentChatID: chat.id)
        for args: [String: Any] in [
            ["chat_id": foreign.id.uuidString], ["before_message_id": foreignMessage.id.uuidString],
            ["limit": true], ["limit": 0], ["limit": 1.5], ["limit": -1],
            ["content_offset": 2], ["read_message_id": "invalid"],
        ] {
            #expect(try await tool.execute(call(args), agent: agent).isError)
        }
    }

    @Test func oversizedGraphemeReturnsABoundedError() async throws {
        let (container, agent, chat) = try store()
        let text = "a" + String(repeating: "\u{0301}", count: 12000)
        #expect(text.count == 1)
        let message = insert(text, chat: chat, context: container.mainContext)
        try container.mainContext.save()
        let read = GetChatTranscriptTool(currentChatID: chat.id)
        for args in [
            ["read_message_id": message.id.uuidString],
            ["around_message_id": message.id.uuidString],
        ] {
            let output = try await read.execute(call(args), agent: agent)
            #expect(output.isError)
            #expect(output.content.utf8.count <= 10000)
        }
        let search = SearchChatTranscriptTool(currentChatID: chat.id)
        let output = try await search.execute(call(["query": text]), agent: agent)
        #expect(output.isError)
        #expect(output.content.utf8.count <= 10000)
    }

    @Test func literalSearchPreservesAccentsAndUsesOneCaseRule() async throws {
        let (container, agent, chat) = try store()
        let plain = insert("RESUME Istanbul", chat: chat, context: container.mainContext, time: 1)
        let accented = insert(
            "résumé İstanbul",
            chat: chat,
            context: container.mainContext,
            time: 2
        )
        try container.mainContext.save()
        let tool = SearchChatTranscriptTool(currentChatID: chat.id)
        for (query, expected) in [
            ("resume", plain.id),
            ("RÉSUMÉ", accented.id),
            ("istanbul", plain.id),
        ] {
            let page = try await result(tool.execute(call(["query": query]), agent: agent))
            let hits = try #require(page["hits"] as? [[String: Any]])
            #expect(hits.compactMap { $0["message_id"] as? String } == [expected.uuidString])
        }
    }

    @Test func boundedSearchCanContinueAfterAPageWithoutMatches() async throws {
        let (container, agent, chat) = try store()
        let older = insert("needle", chat: chat, context: container.mainContext, time: 0)
        for i in 1 ... 1000 {
            _ = insert(
                "other text",
                chat: chat,
                context: container.mainContext,
                time: Double(i)
            )
        }
        try container.mainContext.save()
        let tool = SearchChatTranscriptTool(currentChatID: chat.id)
        let first = try await result(tool.execute(call(["query": "needle"]), agent: agent))
        #expect((first["hits"] as? [[String: Any]])?.isEmpty == true)
        let cursor = try #require(first["next_before_message_id"] as? String)
        let next = try await result(tool.execute(
            call(["query": "needle", "before_message_id": cursor]),
            agent: agent
        ))
        #expect((next["hits"] as? [[String: Any]])?.first?["message_id"] as? String == older.id
            .uuidString)
    }
}
