import Foundation

/// Bundles the inputs needed to start a live call session.
///
/// Groups the agent, provider, conversation state, permissions,
/// and callbacks that ``LiveCallService/start(context:)`` requires.
@MainActor
struct LiveCallContext {
    let agent: Agent
    let provider: Provider
    let messages: [ChatMessage]

    // Permissions & tool context
    let permissionPolicy: AgentPermissionPolicy
    let chatID: UUID?
    let spaceID: UUID?
    let space: Space?
    let mcpServers: [MCPServer]
    let integrations: [Integration]

    // Callbacks
    var onPersist: (([ChatMessage]) -> Void)?
    var onChatGrant: (([ToolCapability]) -> Void)?
    /// Invoked with the underlying error when the call ends abnormally.
    var onError: ((Error) -> Void)?
}
