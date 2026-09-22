import Factory
import Foundation
import SwiftData

/// The pieces of app state a watch-triggered turn needs, resolved from the
/// model container rather than from view state.
@MainActor
struct WatchAgentContext {
    enum Failure: Error {
        case noAgent
        case noProvider
    }

    let agent: Agent
    let provider: Provider
    let chat: Chat
    let permissionPolicy: AgentPermissionPolicy
    let mcpServers: [MCPServer]
    let integrations: [Integration]
    let modelContext: ModelContext

    /// Resolves against the persistent watch chat, so context carries across
    /// wrist taps. The chat follows the primary agent: if the user has
    /// switched agents since the last ask, the chat re-points to the new one.
    static func resolve() throws -> WatchAgentContext {
        let context = Container.shared.modelContainer().mainContext

        var agentDescriptor = Agent.primaryDescriptor
        agentDescriptor.fetchLimit = 1
        guard let agent = (try? context.fetch(agentDescriptor))?.first else {
            throw Failure.noAgent
        }

        let providerID = agent.providerID
        var providerDescriptor = FetchDescriptor<Provider>(
            predicate: #Predicate { $0.id == providerID }
        )
        providerDescriptor.fetchLimit = 1
        guard let provider = (try? context.fetch(providerDescriptor))?.first else {
            throw Failure.noProvider
        }

        let chat = WatchChat.resolve(in: context, agentID: agent.id)
        if chat.agentID != agent.id {
            // The primary agent changed since the last ask — the conversation
            // follows, so the next turn runs on who's currently in charge.
            chat.agentID = agent.id
        }
        let stored = PermissionPolicyLoader.load(
            for: agent, chatID: chat.id, modelContext: context
        )

        return WatchAgentContext(
            agent: agent,
            provider: provider,
            chat: chat,
            // Nobody can answer a permission sheet from a wrist, so a tool set
            // to "ask" resolves to deny rather than hanging the turn.
            permissionPolicy: AgentPermissionPolicy(
                builtInGrants: stored.builtInGrants,
                discoveredGrants: stored.discoveredGrants,
                chatGrants: stored.chatGrants,
                canPromptUser: false
            ),
            mcpServers: (try? context.fetch(
                FetchDescriptor<MCPServer>(predicate: #Predicate { $0.isEnabled })
            )) ?? [],
            integrations: (try? context.fetch(
                FetchDescriptor<Integration>(predicate: #Predicate { $0.isEnabled })
            )) ?? [],
            modelContext: context
        )
    }

    /// The chat so far, oldest first, ready for the API.
    var messages: [ChatMessage] {
        chat.messages
            .sorted { $0.timestamp < $1.timestamp }
            .map { $0.toChatMessage() }
    }

    /// Appends messages to the watch chat.
    func persist(_ chatMessages: [ChatMessage]) {
        for chatMessage in chatMessages {
            let message = Message.from(chatMessage)
            message.chat = chat
            modelContext.insert(message)
        }
        chat.updatedAt = .now
    }
}
