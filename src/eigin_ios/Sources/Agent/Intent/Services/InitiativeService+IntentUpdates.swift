import Foundation
import SwiftData

extension InitiativeService {
    /// Saves intent edits and their notification changes through one validated transaction.
    func updateIntent(
        id: UUID, content: String?, tasks: [IntentTask]?, events: [IntentEvent]?,
        schedules: [IntentSchedule]
    ) async throws {
        guard !working else { throw InitiativeError.busy }
        working = true
        defer { finish() }
        let context = ModelContext(modelContainer)
        guard let intent = try context.fetch(FetchDescriptor<Intent>())
            .first(where: { $0.id == id })
        else {
            throw IntentServiceError.notFound(id: id)
        }
        let agreements = try context.fetch(FetchDescriptor<IntentInitiative>()).filter {
            $0.intentID == id && $0.enabled && intent.intentStatus == .active
        }
        let rescheduled = agreements.filter { agreement in
            guard let next = schedules.first(where: { $0.id == agreement.scheduleID })
            else { return false }
            return intent.schedules.first(where: { $0.id == agreement.scheduleID }) != next
        }
        if !rescheduled.isEmpty {
            guard await NotificationPermission.requestIfNeeded(
                canPromptUser: false,
                authorization: scheduler.authorization
            ) else {
                throw InitiativeError.permissionRequired
            }
            for agreement in rescheduled {
                guard let schedule = schedules.first(where: { $0.id == agreement.scheduleID })
                else { continue }
                _ = try InitiativeRecurrenceCompiler.compile([
                    InitiativeSchedule(
                        initiativeID: agreement.id,
                        intentID: id,
                        agentID: intent.agentID,
                        spaceID: intent.spaceID,
                        schedule: schedule
                    ),
                ], availableRequestCount: 7)
            }
        }
        if let content { intent.content = content }
        if let tasks { intent.tasks = tasks }
        if let events { intent.events = events }
        intent.schedules = schedules
        intent.updatedAt = .now
        for agreement in rescheduled {
            agreement.updatedAt = .now
            agreement.registrationStatus = "pending"
        }
        if !rescheduled.isEmpty {
            let pending = await scheduler.notifications.pending()
            let otherCount = pending
                .count(where: { !$0.identifier.hasPrefix(InitiativeNotificationScheduler.prefix) })
            _ = try scheduler.compile(
                context: context,
                otherRequestCount: otherCount,
                strict: false
            )
        }
        try context.save()
        do { try await scheduler.reconcile(context: context) }
        catch InitiativeError.permissionRequired where rescheduled.isEmpty {
            // Cancellation and metadata-only edits remain available without permission.
        }
    }
}
