import EiginSDK
import Foundation
import SwiftData

/// Applies SDK selections to request copies and retains stable identities across turns.
@MainActor
final class ContextPagingSession {
    typealias Context = EiginSDK.Experimental.Context

    enum Failure: Error, LocalizedError {
        case requestTooLarge, chatUnavailable
        var errorDescription: String? {
            switch self {
            case .requestTooLarge: Localized.Chat.contextTooLarge
            case .chatUnavailable: Localized.Chat.unavailable
            }
        }
    }

    typealias State = ContextPageState

    static let notice = Prompt.Hints.Chat.contextPaged
    private(set) var state: State
    private let chatID: UUID?
    private let agentID: UUID?
    private let context: ModelContext?
    private var record: ContextPage?
    private var durableState = State()

    init(state: State = State()) {
        self.state = state
        chatID = nil
        agentID = nil
        context = nil
    }

    init(agent: Agent, chatID: UUID?) throws {
        state = State()
        context = agent.modelContext
        self.chatID = chatID
        agentID = agent.id
        try refreshStoredState()
    }

    private func refreshStoredState() throws {
        guard let chat = try currentChat(), let context else { return }
        let id = chat.id
        var query = FetchDescriptor<ContextPage>(predicate: #Predicate { $0.chatID == id })
        query.fetchLimit = 1
        record = try context.fetch(query).first
        if let record {
            guard record.agentID == agentID else { throw Failure.chatUnavailable }
            let stored = try JSONDecoder().decode(State.self, from: record.stateData)
            guard stored.version == 1 else { throw Context.PagingError.invalidInput }
            durableState = stored
            // Another surface may have paged this chat since this session was created.
            state.excludedIDs.formUnion(stored.excludedIDs)
            state.maskedIDs.formUnion(stored.maskedIDs)
            state.maskedIDs.subtract(state.excludedIDs)
            state.hasPaged = state.hasPaged || stored.hasPaged
            state.hintedUserIDs.formUnion(stored.hintedUserIDs)
        }
    }

    private func currentChat() throws -> Chat? {
        guard let chatID else { return nil }
        guard let context, let chat = ChatLookup.find(chatID, in: context),
              chat.agentID == agentID
        else {
            throw Failure.chatUnavailable
        }
        return chat
    }

    /// Deletes selection bookkeeping alongside a deleted or replaced chat.
    static func remove(chatID: UUID, context: ModelContext) throws {
        try context.delete(model: ContextPage.self, where: #Predicate { $0.chatID == chatID })
    }

    /// Rejects a smaller hedge/retry candidate before sending an oversized request.
    static func validate(
        _ messages: [ChatMessage],
        tools: [ToolDefinition]?,
        model: String,
        origin: ReasoningOrigin?
    ) throws {
        let tokens = TokenEstimator.estimateRequest(
            messages: messages.map { $0.reasoningScoped(to: origin) },
            toolDefinitions: tools, model: model
        )
        guard tokens <= policy(model: model).maximumTokens else { throw Failure.requestTooLarge }
    }

    /// Size-aware input budgets, after reserving generation and estimator headroom.
    static func policy(contextWindow: Int, maxOutput: Int) -> Context.PagingPolicy {
        Context.defaultPagingPolicy(contextWindow: contextWindow, maxOutput: maxOutput)
    }

    static func policy(model: String) -> Context.PagingPolicy {
        let catalog = KnownModelCatalog.lookup(model)
        return policy(
            contextWindow: catalog?.contextWindow ?? 128_000,
            maxOutput: catalog?.maxOutput ?? 4096
        )
    }

    /// Shapes the complete outgoing request. Originals remain available for checkpoints.
    func prepare(
        _ messages: [ChatMessage], tools: [ToolDefinition]?, model: String,
        origin: ReasoningOrigin?, policy override: Context.PagingPolicy? = nil
    ) throws -> [ChatMessage] {
        try refreshStoredState()
        let started = ContinuousClock.now
        let policy = override ?? Self.policy(model: model)
        let visible = messages.filter { !state.excludedIDs.contains(Self.identity($0)) }
        let firstUser = visible.firstIndex { $0.role == "user" } ?? visible.count
        let prefix = Array(visible[..<firstUser])
        let history = Array(visible[firstUser...])
        var budgetHintIDs = state.hintedUserIDs
        if state.hasPaged, let latest = history.last(where: { $0.role == "user" }) {
            budgetHintIDs.insert(Self.identity(latest))
        }
        let scoped = Self.withPagingHints(history, userIDs: budgetHintIDs)
            .map { $0.reasoningScoped(to: origin) }
        let baseCost = TokenEstimator.estimateRequest(
            messages: prefix.map { $0.reasoningScoped(to: origin) },
            toolDefinitions: tools, model: model
        )
        let noticeCost = state.hasPaged ? 0 : TokenEstimator.estimate(Self.notice) + 12
        guard baseCost <= policy.maximumTokens - noticeCost else { throw Failure.requestTooLarge }
        let fixed = baseCost + noticeCost
        let previous = Context.PageSelection(maskedResultIndices: history.indices.filter {
            state.maskedIDs.contains(Self.identity(history[$0]))
        })
        let result: Context.PagingResult
        do {
            result = try Context.page(
                messages: ContextSDK.messages(scoped, model: model), previous: previous,
                policy: policy,
                fixedInputTokens: fixed
            )
        } catch Context.PagingError.protectedContentTooLarge {
            throw Failure.requestTooLarge
        }
        var next = state
        for message in history.prefix(result.selection.retainedStart) {
            next.excludedIDs.insert(Self.identity(message))
        }
        for index in result.selection.maskedResultIndices {
            next.maskedIDs.insert(Self.identity(history[index]))
        }
        next.maskedIDs.subtract(next.excludedIDs)
        next.hasPaged = next.hasPaged || result.changed
        var output = prefix + history.enumerated().compactMap { index, message -> ChatMessage? in
            guard index >= result.selection.retainedStart else { return nil }
            guard next.maskedIDs.contains(Self.identity(message)) else { return message }
            var copy = message
            copy.content = "[omitted]"
            copy.attachments = nil
            return copy
        }
        if next.hasPaged, let latest = output.last(where: { $0.role == "user" }) {
            next.hintedUserIDs.insert(Self.identity(latest))
        }
        next.hintedUserIDs.subtract(next.excludedIDs)
        output = Self.withPagingHints(output, userIDs: next.hintedUserIDs)
        // Save only identities already in the transcript; current-turn selections stay in memory.
        if next != state { try persist(next) }
        if result.changed {
            AppLogger.info(
                "Context paged: retained \(public: output.count)/\(public: messages.count) messages, \(public: result.selection.maskedResultIndices.count) masked results, ~\(public: result.estimatedTokens) input tokens, \(public: String(describing: started.duration(to: .now)))",
                category: .chat
            )
        }
        state = next
        return output
    }

    private func persist(_ next: State) throws {
        guard let chat = try currentChat(), let context else { return }
        let id = chat.id
        var durable = durableState.excludedIDs.union(durableState.maskedIDs)
        durable.formUnion(durableState.hintedUserIDs)
        durable.formUnion(["context-summary", "context-summary-ack"])
        var candidates = next.excludedIDs.union(next.maskedIDs)
        candidates.formUnion(next.hintedUserIDs)
        let unresolved = candidates.subtracting(durable).compactMap(UUID.init(uuidString:))
        for start in stride(from: 0, to: unresolved.count, by: 200) {
            let ids = Array(unresolved[start ..< min(start + 200, unresolved.count)])
            var descriptor =
                FetchDescriptor<Message>(predicate: #Predicate {
                    $0.chat?.id == id && ids.contains($0.id)
                })
            descriptor.propertiesToFetch = [\.id]
            try durable.formUnion(context.fetch(descriptor).map { $0.id.uuidString })
        }
        var saved = next
        saved.excludedIDs.formIntersection(durable)
        saved.maskedIDs.formIntersection(durable)
        saved.hintedUserIDs.formIntersection(durable)
        let data = try JSONEncoder().encode(saved)
        if let record {
            record.stateData = data
        } else {
            let created = ContextPage(chatID: chat.id, agentID: chat.agentID, stateData: data)
            context.insert(created)
            record = created
        }
        try context.save()
        durableState = saved
    }

    private static func withPagingHints(
        _ messages: [ChatMessage],
        userIDs: Set<String>
    ) -> [ChatMessage] {
        guard let hint = SystemHintBuilder.build(sections: [notice]) else { return messages }
        return messages.map { message in
            guard message.role == "user",
                  userIDs.contains(identity(message)) else { return message }
            return MessagePreparationSDKConversion.appendHint(hint, to: [message])[0]
        }
    }

    private static func identity(_ message: ChatMessage) -> String {
        message.localID.hasPrefix("msg-") ? String(message.localID.dropFirst(4)) : message.localID
    }
}
