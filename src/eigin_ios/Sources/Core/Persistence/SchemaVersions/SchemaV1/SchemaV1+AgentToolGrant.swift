import Foundation
import SwiftData

extension SchemaV1 {
    @Model
    final class AgentToolGrant {
        var id: UUID
        var agentID: UUID
        var kind: GrantKind
        var key: String
        var level: ToolPermissionLevel

        init(agentID: UUID, kind: GrantKind, key: String, level: ToolPermissionLevel) {
            id = UUID()
            self.agentID = agentID
            self.kind = kind
            self.key = key
            self.level = level
        }

        init(agentID: UUID, capability: ToolCapability, level: ToolPermissionLevel) {
            id = UUID()
            self.agentID = agentID
            kind = capability.kind
            key = capability.key
            self.level = level
        }
    }
}
