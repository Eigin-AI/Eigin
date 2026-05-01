import Foundation
import SwiftData

/// Builds an ``AgentPermissionPolicy`` from persisted grants.
@MainActor
enum PermissionPolicyLoader {
    /// Loads the permission policy for an agent in a given chat.
    static func load(
        for agent: Agent,
        chatID: UUID?,
        modelContext: ModelContext
    ) -> AgentPermissionPolicy {
        let agentID = agent.id
        let agentGrantDescriptor = FetchDescriptor<AgentToolGrant>(
            predicate: #Predicate { $0.agentID == agentID }
        )
        let agentGrantRows = (try? modelContext.fetch(agentGrantDescriptor)) ?? []

        var builtInGrants: [String: ToolPermissionLevel] = [:]
        var discoveredGrants: [String: ToolPermissionLevel] = [:]
        for row in agentGrantRows {
            if row.kind == .discovered {
                discoveredGrants[row.key] = row.level
            } else {
                builtInGrants[row.key] = row.level
            }
        }

        let resolvedChatID = chatID ?? UUID()
        let chatGrantDescriptor = FetchDescriptor<ChatToolGrant>(
            predicate: #Predicate { $0.chatID == resolvedChatID }
        )
        let chatGrantRows = (try? modelContext.fetch(chatGrantDescriptor)) ?? []
        let chatGrants = Set(chatGrantRows.map(\.key))

        return AgentPermissionPolicy(
            builtInGrants: builtInGrants,
            discoveredGrants: discoveredGrants,
            chatGrants: chatGrants,
            canPromptUser: true
        )
    }
}
