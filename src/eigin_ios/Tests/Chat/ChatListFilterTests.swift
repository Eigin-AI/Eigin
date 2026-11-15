@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("ChatListFilter.visibleChats")
@MainActor
struct ChatListFilterTests {
    private let agentID = UUID()
    private let container: ModelContainer

    init() throws {
        container = try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func space(isPrivate: Bool) -> Space {
        let space = Space(agentID: agentID)
        space.isPrivate = isPrivate
        return space
    }

    /// Chats the filter should show: made real with one message.
    private func startedChat(spaceID: UUID?) -> Chat {
        let chat = Chat(agentID: agentID, spaceID: spaceID)
        chat.messages = [Message(role: "user", content: "hi")]
        return chat
    }

    @Test("Default view hides private-space chats")
    func defaultHidesPrivate() throws {
        let privateSpace = space(isPrivate: true)
        let privateChat = startedChat(spaceID: privateSpace.id)
        let publicChat = startedChat(spaceID: nil)

        let result = try visibleChats(
            [privateChat, publicChat],
            spaces: [privateSpace],
            selectedSpaceID: nil
        )

        #expect(result.map(\.id) == [publicChat.id])
    }

    @Test("Default view keeps public-space and space-less chats")
    func defaultKeepsVisible() throws {
        let publicSpace = space(isPrivate: false)
        let publicChat = startedChat(spaceID: publicSpace.id)
        let looseChat = startedChat(spaceID: nil)

        let result = try visibleChats(
            [publicChat, looseChat],
            spaces: [publicSpace],
            selectedSpaceID: nil
        )

        #expect(Set(result.map(\.id)) == Set([publicChat.id, looseChat.id]))
    }

    @Test("Selecting a private space shows its chats")
    func selectingPrivateShowsChats() throws {
        let privateSpace = space(isPrivate: true)
        let privateChat = startedChat(spaceID: privateSpace.id)
        let looseChat = startedChat(spaceID: nil)

        let result = try visibleChats(
            [privateChat, looseChat],
            spaces: [privateSpace],
            selectedSpaceID: privateSpace.id
        )

        #expect(result.map(\.id) == [privateChat.id])
    }

    @Test("Selecting a public space shows its chats")
    func selectingPublicShowsChats() throws {
        let publicSpace = space(isPrivate: false)
        let publicChat = startedChat(spaceID: publicSpace.id)
        let otherChat = startedChat(spaceID: UUID())

        let result = try visibleChats(
            [publicChat, otherChat],
            spaces: [publicSpace],
            selectedSpaceID: publicSpace.id
        )

        #expect(result.map(\.id) == [publicChat.id])
    }

    @Test("Empty chats are hidden")
    func emptyChatsHidden() throws {
        let emptyChat = Chat(agentID: agentID)
        let usedSpace = space(isPrivate: false)
        let populatedChat = startedChat(spaceID: usedSpace.id)

        let result = try visibleChats(
            [emptyChat, populatedChat],
            spaces: [usedSpace],
            selectedSpaceID: nil
        )

        #expect(result.map(\.id) == [populatedChat.id])
    }

    @Test("Empty chats are hidden in an explicitly selected space")
    func emptyChatsHiddenInSelectedSpace() throws {
        let space1 = space(isPrivate: false)
        let emptyChat = Chat(agentID: agentID, spaceID: space1.id)
        let populatedChat = startedChat(spaceID: space1.id)

        let result = try visibleChats(
            [emptyChat, populatedChat],
            spaces: [space1],
            selectedSpaceID: space1.id
        )

        #expect(result.map(\.id) == [populatedChat.id])
    }

    private func visibleChats(
        _ chats: [Chat],
        spaces: [Space],
        selectedSpaceID: UUID?
    ) throws -> [Chat] {
        let context = container.mainContext
        for space in spaces {
            context.insert(space)
        }
        for chat in chats {
            context.insert(chat)
        }
        try context.save()
        return try ChatListFilter.visibleChats(
            context.fetch(ChatListQueries.populatedChats),
            spaces: spaces,
            selectedSpaceID: selectedSpaceID
        )
    }
}
