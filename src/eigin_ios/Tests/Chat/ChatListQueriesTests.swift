@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Chat list store queries")
@MainActor
struct ChatListQueriesTests {
    @Test("Eligibility includes every role and follows first insertion and last deletion")
    func eligibility() throws {
        try withStore { context in
            let chat = Chat(agentID: UUID())
            context.insert(chat)
            try context.save()
            #expect(try context.fetch(ChatListQueries.populatedChats).isEmpty)
            #expect(try context.fetch(ChatListQueries.emptyChats).map(\.id) == [chat.id])

            let message = Message(role: "tool", content: "")
            message.chat = chat
            context.insert(message)
            // Pending first messages must protect a chat from appearance cleanup.
            #expect(try context.fetch(ChatListQueries.populatedChats).map(\.id) == [chat.id])
            #expect(try context.fetch(ChatListQueries.emptyChats).isEmpty)
            try context.save()
            #expect(try context.fetch(ChatListQueries.populatedChats).map(\.id) == [chat.id])
            #expect(try context.fetch(ChatListQueries.preview(chat: chat)).isEmpty)

            context.delete(message)
            try context.save()
            #expect(try context.fetch(ChatListQueries.populatedChats).isEmpty)
            #expect(try context.fetch(ChatListQueries.emptyChats).map(\.id) == [chat.id])
        }
    }

    @Test("Preview selects the latest nonempty conversational message in its own chat")
    func preview() throws {
        try withStore { context in
            let chat = Chat(agentID: UUID())
            let other = Chat(agentID: UUID())
            context.insert(chat)
            context.insert(other)
            let first = append("user", "Question", time: 1, chat: chat, context: context)
            let answer = append("assistant", "Answer", time: 2, chat: chat, context: context)
            append("assistant", "", time: 3, chat: chat, context: context)
            append("tool", "Tool result", time: 4, chat: chat, context: context)
            append("system", "System", time: 5, chat: chat, context: context)
            append("user", "Other chat", time: 6, chat: other, context: context)
            try context.save()
            #expect(try context.fetch(ChatListQueries.preview(chat: chat))
                .map(\.id) == [answer.id])

            answer.content = ""
            try context.save()
            #expect(try context.fetch(ChatListQueries.preview(chat: chat))
                .map(\.id) == [first.id])
            let newest = append("assistant", "New answer", time: 7, chat: chat, context: context)
            #expect(try context.fetch(ChatListQueries.preview(chat: chat))
                .map(\.id) == [newest.id])
            try context.save()
            #expect(try context.fetch(ChatListQueries.preview(chat: chat))
                .map(\.id) == [newest.id])
            context.delete(newest)
            try context.save()
            #expect(try context.fetch(ChatListQueries.preview(chat: chat))
                .map(\.id) == [first.id])
        }
    }

    @discardableResult
    private func append(
        _ role: String,
        _ content: String,
        time: Double,
        chat: Chat,
        context: ModelContext
    ) -> Message {
        let message = Message(role: role, content: content)
        message.timestamp = Date(timeIntervalSince1970: time)
        message.chat = chat
        context.insert(message)
        return message
    }

    private func withStore(_ operation: (ModelContext) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            configurations: ModelConfiguration(url: directory
                .appendingPathComponent("store.sqlite"))
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try operation(context)
    }
}
