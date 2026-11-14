import Foundation
import SwiftData

extension SchemaV16 {
    /// Request selection metadata; transcript rows remain unchanged.
    @Model
    final class ContextPage {
        var chatID: UUID
        var agentID: UUID
        var stateData: Data

        init(chatID: UUID, agentID: UUID, stateData: Data) {
            self.chatID = chatID
            self.agentID = agentID
            self.stateData = stateData
        }
    }
}
