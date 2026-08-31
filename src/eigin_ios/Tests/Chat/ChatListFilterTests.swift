@testable import Eigin
import Foundation
import Testing

@Suite("ChatListFilter.visibleChats")
struct ChatListFilterTests {
    private let agentID = UUID()

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
    func defaultHidesPrivate() {
        let privateSpace = space(isPrivate: true)
        let privateChat = Chat(agentID: agentID, spaceID: privateSpace.id)

        let result = ChatListFilter.visibleChats(
            [privateChat],
            spaces: [privateSpace],
            selectedSpaceID: nil
        )

        #expect(result.isEmpty)
    }

    @Test("Default view keeps public-space and space-less chats")
    func defaultKeepsVisible() {
        let publicSpace = space(isPrivate: false)
        let publicChat = startedChat(spaceID: publicSpace.id)
        let looseChat = startedChat(spaceID: nil)

        let result = ChatListFilter.visibleChats(
            [publicChat, looseChat],
            spaces: [publicSpace],
            selectedSpaceID: nil
        )

        #expect(Set(result.map(\.id)) == Set([publicChat.id, looseChat.id]))
    }

    @Test("Selecting a private space shows its chats")
    func selectingPrivateShowsChats() {
        let privateSpace = space(isPrivate: true)
        let privateChat = startedChat(spaceID: privateSpace.id)
        let looseChat = startedChat(spaceID: nil)

        let result = ChatListFilter.visibleChats(
            [privateChat, looseChat],
            spaces: [privateSpace],
            selectedSpaceID: privateSpace.id
        )

        #expect(result.map(\.id) == [privateChat.id])
    }

    @Test("Selecting a public space shows its chats")
    func selectingPublicShowsChats() {
        let publicSpace = space(isPrivate: false)
        let publicChat = startedChat(spaceID: publicSpace.id)
        let otherChat = startedChat(spaceID: UUID())

        let result = ChatListFilter.visibleChats(
            [publicChat, otherChat],
            spaces: [publicSpace],
            selectedSpaceID: publicSpace.id
        )

        #expect(result.map(\.id) == [publicChat.id])
    }

    @Test("Empty chats are hidden")
    func emptyChatsHidden() {
        let emptyChat = Chat(agentID: agentID)
        let usedSpace = space(isPrivate: false)
        let populatedChat = startedChat(spaceID: usedSpace.id)

        let result = ChatListFilter.visibleChats(
            [emptyChat, populatedChat],
            spaces: [usedSpace],
            selectedSpaceID: nil
        )

        #expect(result.map(\.id) == [populatedChat.id])
    }

    @Test("Empty chats are hidden in an explicitly selected space")
    func emptyChatsHiddenInSelectedSpace() {
        let space1 = space(isPrivate: false)
        let emptyChat = Chat(agentID: agentID, spaceID: space1.id)
        let populatedChat = startedChat(spaceID: space1.id)

        let result = ChatListFilter.visibleChats(
            [emptyChat, populatedChat],
            spaces: [space1],
            selectedSpaceID: space1.id
        )

        #expect(result.map(\.id) == [populatedChat.id])
    }
}
