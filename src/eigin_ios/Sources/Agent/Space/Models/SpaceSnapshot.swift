import Foundation

struct SpaceSnapshot: Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let instructions: String

    init(id: UUID, name: String, emoji: String = "", instructions: String = "") {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.instructions = instructions
    }

    init(id: UUID, name: String, instructions: String) {
        self.id = id
        self.name = name
        emoji = ""
        self.instructions = instructions
    }
}
