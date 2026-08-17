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
        let publicChat = Chat(agentID: agentID, spaceID: publicSpace.id)
        let looseChat = Chat(agentID: agentID, spaceID: nil)

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
        let privateChat = Chat(agentID: agentID, spaceID: privateSpace.id)
        let looseChat = Chat(agentID: agentID, spaceID: nil)

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
        let publicChat = Chat(agentID: agentID, spaceID: publicSpace.id)
        let otherChat = Chat(agentID: agentID, spaceID: UUID())

        let result = ChatListFilter.visibleChats(
            [publicChat, otherChat],
            spaces: [publicSpace],
            selectedSpaceID: publicSpace.id
        )

        #expect(result.map(\.id) == [publicChat.id])
    }
}
