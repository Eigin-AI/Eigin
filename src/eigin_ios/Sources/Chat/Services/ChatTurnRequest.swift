import Foundation

/// App values supplied once for a complete turn.
@MainActor
struct ChatTurnRequest {
    let messages: [ChatMessage]
    let tools: [ToolDefinition]?
    let agent: Agent
    let provider: Provider
    let model: String
    let cacheKey: String?
    let sentAt: ContinuousClock.Instant?
    let routing: RouteRequest?
    let conversationID: UUID?
    let initialInstruction: String?
    let propagatesStreamCancellation: Bool
}

/// App capabilities used to prepare and execute the turn.
@MainActor
struct ChatTurnEnvironment {
    let paging: ContextPagingSession
    let routing: InferenceRoutingContext
    let chatService: ChatService
    let executor: ToolExecutor
    let refreshCatalog: @MainActor @Sendable (UUID) async -> RoutingProvider?
}
