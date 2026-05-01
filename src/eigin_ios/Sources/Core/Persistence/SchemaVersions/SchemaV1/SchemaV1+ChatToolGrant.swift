import Foundation
import SwiftData

extension SchemaV1 {
    @Model
    final class ChatToolGrant {
        var id: UUID
        var chatID: UUID
        var kind: GrantKind
        var key: String

        init(chatID: UUID, kind: GrantKind, key: String) {
            id = UUID()
            self.chatID = chatID
            self.kind = kind
            self.key = key
        }

        init(chatID: UUID, capability: ToolCapability) {
            id = UUID()
            self.chatID = chatID
            kind = capability.kind
            key = capability.key
        }
    }
}
