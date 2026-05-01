import Foundation
import SwiftData

extension SchemaV1 {
    @Model
    final class Chat {
        var id: UUID
        var agentID: UUID
        var spaceID: UUID?
        var title: String
        var titleOriginRaw: TitleOrigin
        var createdAt: Date
        var updatedAt: Date
        var needsCompaction: Bool = false
        var activeSkillEntries: [ActiveSkillEntry] = []

        @Relationship(deleteRule: .cascade, inverse: \Message.chat)
        var messages: [Message]

        /// Skill IDs currently active in this chat.
        var activeSkillIDs: [String] {
            activeSkillEntries.map(\.skillID)
        }

        func isSkillActive(_ id: String) -> Bool {
            activeSkillEntries.contains { $0.skillID == id }
        }

        /// Clears all active skills (e.g. after compaction).
        func clearActiveSkills() {
            activeSkillEntries.removeAll()
        }

        var titleOrigin: TitleOrigin {
            get { titleOriginRaw }
            set { titleOriginRaw = newValue }
        }

        var lastVisibleMessage: Message? {
            messages
                .filter { ($0.role == "user" || $0.role == "assistant") && !$0.content.isEmpty }
                .max(by: { $0.timestamp < $1.timestamp })
        }

        init(agentID: UUID, spaceID: UUID? = nil, title: String = "") {
            id = UUID()
            self.agentID = agentID
            self.spaceID = spaceID
            self.title = title
            titleOriginRaw = .none
            createdAt = .now
            updatedAt = .now
            messages = []
        }
    }
}
