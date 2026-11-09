import Foundation
import SwiftData

/// Creates one conversation per delivered occurrence and claims its first turn durably.
@MainActor enum InitiativeConversationService {
    private static var activeChats = Set<UUID>()

    /// Claims every first execution path, including explicit retries after setup errors.
    static func beginExecution(
        chatID: UUID,
        messages: [ChatMessage],
        context: ModelContext
    ) throws -> Bool {
        try validateTurn(chatID: chatID, messages: messages, context: context)
        guard !messages.contains(where: { $0.role == "user" }) else { return false }
        guard let occurrence = try context.fetch(FetchDescriptor<InitiativeOccurrence>())
            .first(where: { $0.chatID == chatID }),
            occurrence.completedAt == nil else { return false }
        guard !activeChats.contains(chatID) else { throw InitiativeError.busy }
        occurrence.startedAt = occurrence.startedAt ?? .now
        try context.save()
        activeChats.insert(chatID)
        return true
    }

    /// Associates only user-visible output persisted during this occurrence's active execution.
    static func recordOutput(_ message: Message, chatID: UUID, context: ModelContext) {
        guard activeChats.contains(chatID), message.role == "assistant", !message.content.isEmpty,
              !message.isCompactionSummary,
              let occurrence = try? context.fetch(FetchDescriptor<InitiativeOccurrence>())
              .first(where: { $0.chatID == chatID }),
              !occurrence.outputMessageIDs.contains(message.id) else { return }
        occurrence.outputMessageIDs.append(message.id)
    }

    /// Persists a completed turn; ambiguous or failed executions remain explicitly resumable.
    static func finishExecution(chatID: UUID, completed: Bool, context: ModelContext) throws {
        defer { activeChats.remove(chatID) }
        guard let occurrence = try context.fetch(FetchDescriptor<InitiativeOccurrence>())
            .first(where: { $0.chatID == chatID }) else { return }
        if completed { occurrence.completedAt = .now }
        try context.save()
    }

    /// An unfinished claim without an in-process run needs explicit recovery.
    static func needsResume(chatID: UUID, context: ModelContext) -> Bool {
        guard !activeChats.contains(chatID) else { return false }
        return (try? context.fetch(FetchDescriptor<InitiativeOccurrence>()).contains {
            $0.chatID == chatID && $0.startedAt != nil && $0.completedAt == nil
        }) ?? false
    }

    static func open(
        registrationID: String,
        deliveredAt: Date,
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> UUID {
        guard deliveredAt.timeIntervalSince1970.isFinite
        else { throw InitiativeError.staleNotification }
        let key = registrationID + ":" + String(deliveredAt.timeIntervalSince1970)
        if let occurrence = try context.fetch(FetchDescriptor<InitiativeOccurrence>())
            .first(where: { $0.id == key })
        {
            guard try context.fetch(FetchDescriptor<Chat>())
                .contains(where: { $0.id == occurrence.chatID })
            else {
                throw InitiativeError.missingChat
            }
            return occurrence.chatID
        }
        guard let registration = try context.fetch(FetchDescriptor<InitiativeRegistration>())
            .first(where: { $0.id == registrationID })
        else { throw InitiativeError.staleNotification }
        let delivery = try JSONDecoder().decode(InitiativeDelivery.self, from: registration.payload)
        let id = try WaitingInitiativeStore.notificationOccurrenceID(
            delivery: delivery,
            deliveredAt: deliveredAt,
            calendar: calendar
        )
        if try context.fetch(FetchDescriptor<InitiativeOccurrence>())
            .contains(where: { $0.id == id })
        {
            return try WaitingInitiativeStore.open(id: id, context: context)
        }
        try WaitingInitiativeStore.reconcile(context: context, now: now, calendar: calendar)
        return try WaitingInitiativeStore.open(id: id, context: context)
    }

    /// Startup and explicit retry use the same validation before any model or tool execution.
    static func validateTurn(chatID: UUID, messages: [ChatMessage], context: ModelContext) throws {
        guard !messages.contains(where: { $0.role == "user" }),
              let occurrence = try context.fetch(FetchDescriptor<InitiativeOccurrence>())
              .first(where: { $0.chatID == chatID }), occurrence.completedAt == nil else { return }
        _ = try validatedDelivery(registrationID: occurrence.registrationID, context: context)
    }

    static func hasPendingStart(chatID: UUID, context: ModelContext) -> Bool {
        guard (try? hasUserMessage(chatID: chatID, context: context)) == false else { return false }
        return (try? context.fetch(FetchDescriptor<InitiativeOccurrence>())
            .contains { $0.chatID == chatID && $0.startedAt == nil }) ?? false
    }

    /// Returns false for already claimed turns, including crash-ambiguous starts.
    static func claimStart(chatID: UUID, context: ModelContext) throws -> Bool {
        guard try !hasUserMessage(chatID: chatID, context: context) else { return false }
        guard let occurrence = try context.fetch(FetchDescriptor<InitiativeOccurrence>())
            .first(where: { $0.chatID == chatID }),
            occurrence.startedAt == nil else { return false }
        _ = try validatedDelivery(registrationID: occurrence.registrationID, context: context)
        occurrence.startedAt = .now
        do { try context.save() }
        catch { context.rollback(); throw error }
        return true
    }

    private static func hasUserMessage(chatID: UUID, context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<Message>(predicate: #Predicate {
            $0.chat?.id == chatID && $0.role == "user"
        })) > 0
    }

    static func validatedDelivery(
        registrationID: String,
        context: ModelContext
    ) throws -> InitiativeDelivery {
        guard let registration = try context.fetch(FetchDescriptor<InitiativeRegistration>())
            .first(where: { $0.id == registrationID })
        else {
            throw InitiativeError.staleNotification
        }
        let delivery = try JSONDecoder().decode(InitiativeDelivery.self, from: registration.payload)
        guard try context.fetch(FetchDescriptor<Agent>())
            .contains(where: { $0.id == delivery.agentID })
        else { throw InitiativeError.missingChat }
        if let spaceID = delivery.spaceID {
            guard try context.fetch(FetchDescriptor<Space>())
                .contains(where: { $0.id == spaceID && $0.agentID == delivery.agentID })
            else { throw InitiativeError.missingChat }
        }
        let intents = try context.fetch(FetchDescriptor<Intent>())
        let agreements = try context.fetch(FetchDescriptor<IntentInitiative>())
        for member in delivery.members {
            guard let intent = intents.first(where: { $0.id == member.intentID }),
                  intent.agentID == delivery.agentID, intent.spaceID == delivery.spaceID,
                  intent.intentStatus == .active,
                  intent.schedules.contains(member.schedule),
                  agreements.contains(where: {
                      $0.id == member.initiativeID && $0.enabled && $0.intentID == member.intentID
                          && $0.scheduleID == member.schedule.id && $0.instructions == member
                          .instructions
                          && $0.notificationBody == member.body && $0.updatedAt == member.revision
                  }) else { throw InitiativeError.staleNotification }
        }
        guard !delivery.members.isEmpty else { throw InitiativeError.staleNotification }
        return delivery
    }
}
