import Foundation
import Observation
import SwiftData

/// A requested agreement; a supplied schedule updates the existing intent schedule in the same
/// save.
struct InitiativeChange {
    let intentID: UUID
    let scheduleID: UUID
    let instructions: String
    let body: String
    var schedule: IntentSchedule?
}

/// Actionable failures returned by initiative tools and tap handling.
enum InitiativeError: LocalizedError {
    case permissionRequired, inaccessibleIntent, missingSchedule, invalidContent, busy
    case registrationFailed, staleNotification, missingChat, providerUnavailable, interrupted
    case invalidIntentID, invalidScheduleID, invalidInitiativeID, invalidChanges

    var errorDescription: String? {
        switch self {
        case .permissionRequired: Localized.Intent.Errors.permissionRequired
        case .inaccessibleIntent: Localized.Intent.Errors.inaccessibleIntent
        case .missingSchedule: Localized.Intent.Errors.missingSchedule
        case .invalidContent: Localized.Intent.Errors.invalidContent
        case .invalidIntentID: Localized.Intent.Errors.invalidIntentID
        case .invalidScheduleID: Localized.Intent.Errors.invalidScheduleID
        case .invalidInitiativeID: Localized.Intent.Errors.invalidInitiativeID
        case .invalidChanges: Localized.Intent.Errors.invalidChanges
        case .busy: Localized.Intent.Errors.busy
        case .registrationFailed: Localized.Intent.Errors.registrationFailed
        case .staleNotification: Localized.Intent.Errors.staleNotification
        case .interrupted: Localized.Intent.Errors.interrupted
        case .providerUnavailable: Localized.Intent.Errors.providerUnavailable
        case .missingChat: Localized.Intent.Errors.missingChat
        }
    }
}

extension InitiativeScheduleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedMonthlySchedule: Localized.Intent.Errors.unsupportedMonthlySchedule
        case .explicitTimeRequired: Localized.Intent.Errors.explicitTimeRequired
        case .invalidTime: Localized.Intent.Errors.invalidTime
        case .invalidWeekdays: Localized.Intent.Errors.invalidWeekdays
        case .duplicateInitiative: Localized.Intent.Errors.duplicateInitiative
        case .invalidRequestBudget, .capacityExceeded: Localized.Intent.Errors.capacityExceeded
        }
    }
}

/// Owns permission checks, agreement persistence, and serialized notification reconciliation.
@MainActor @Observable final class InitiativeService {
    var waiting: [WaitingMessage] = []
    var isActive = false
    var dueRefresh: Task<Void, Never>?
    let modelContainer: ModelContainer
    let scheduler: InitiativeNotificationScheduler
    var working = false
    private var reconcileAgain = false

    init(
        modelContainer: ModelContainer,
        scheduler: InitiativeNotificationScheduler = InitiativeNotificationScheduler()
    ) {
        self.modelContainer = modelContainer
        self.scheduler = scheduler
    }

    func apply(
        _ changes: [InitiativeChange],
        agentID: UUID,
        spaceID: UUID?,
        canPromptUser: Bool
    ) async throws -> [[String: String]] {
        guard !working else { throw InitiativeError.busy }
        working = true
        defer { finish() }
        let context = ModelContext(modelContainer)
        let intents = try context.fetch(FetchDescriptor<Intent>())
        var agreements = try context.fetch(FetchDescriptor<IntentInitiative>())
        var changedIDs = Set<UUID>()
        for change in changes {
            guard let intent = intents.first(where: { $0.id == change.intentID }),
                  intent.agentID == agentID, intent.spaceID == spaceID,
                  intent.intentStatus == .active
            else {
                throw InitiativeError.inaccessibleIntent
            }
            guard let index = intent.schedules.firstIndex(where: { $0.id == change.scheduleID })
            else {
                throw InitiativeError.missingSchedule
            }
            guard !change.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !change.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  change.body.count <= 200,
                  change.instructions.count <= 4000 else { throw InitiativeError.invalidContent }
            if let schedule = change.schedule {
                guard schedule.id == change.scheduleID
                else { throw InitiativeError.missingSchedule }
                intent.schedules[index] = schedule
                intent.updatedAt = .now
            }
            let agreement: IntentInitiative
            if let existing = agreements
                .first(where: { $0.intentID == intent.id && $0.scheduleID == change.scheduleID })
            {
                agreement = existing
            } else {
                agreement = IntentInitiative(
                    intentID: intent.id,
                    scheduleID: change.scheduleID,
                    instructions: change.instructions,
                    notificationBody: change.body
                )
                context.insert(agreement)
                agreements.append(agreement)
            }
            guard changedIDs.insert(agreement.id).inserted
            else { throw InitiativeScheduleError.duplicateInitiative }
            agreement.instructions = change.instructions
            agreement.notificationBody = change.body
            agreement.enabled = true
            agreement.registrationStatus = "pending"
            agreement.updatedAt = .now
        }
        for agreement in agreements where changedIDs.contains(agreement.id) {
            guard let intent = intents.first(where: { $0.id == agreement.intentID }),
                  let schedule = intent.schedules.first(where: { $0.id == agreement.scheduleID })
            else { throw InitiativeError.missingSchedule }
            _ = try InitiativeRecurrenceCompiler.compile(
                [InitiativeSchedule(
                    initiativeID: agreement.id,
                    intentID: intent.id,
                    agentID: intent.agentID,
                    spaceID: intent.spaceID,
                    schedule: schedule
                )],
                availableRequestCount: 7
            )
        }
        do { try WaitingInitiativeStore.reconcile(context: context) }
        catch { throw InitiativeOperationFailure(underlying: error, changesState: .unknown) }
        do {
            try refreshWaiting()
            await cleanDeliveredNotifications()
            _ = await NotificationPermission.requestIfNeeded(
                canPromptUser: canPromptUser, authorization: scheduler.authorization
            )
            try await scheduler.reconcile(context: context)
            return try list(agentID: agentID, spaceID: spaceID)
        } catch { throw InitiativeOperationFailure(underlying: error, changesState: .saved) }
    }

    func cancel(id: UUID, agentID: UUID, spaceID: UUID?) async throws {
        guard !working else { throw InitiativeError.busy }
        working = true
        defer { finish() }
        let context = ModelContext(modelContainer)
        guard let agreement = try context.fetch(FetchDescriptor<IntentInitiative>())
            .first(where: { $0.id == id }),
            let intent = try context.fetch(FetchDescriptor<Intent>())
            .first(where: { $0.id == agreement.intentID }),
            intent.agentID == agentID,
            intent.spaceID == spaceID else { throw InitiativeError.inaccessibleIntent }
        agreement.enabled = false
        do { try WaitingInitiativeStore.reconcile(context: context) }
        catch { throw InitiativeOperationFailure(underlying: error, changesState: .unknown) }
        do {
            try refreshWaiting()
            await cleanDeliveredNotifications()
            try await scheduler.reconcile(context: context)
        } catch InitiativeError.permissionRequired {
            // Remaining agreements retain their permission error; cancellation is complete.
        } catch { throw InitiativeOperationFailure(underlying: error, changesState: .saved) }
    }

    func schedule(
        intentID: UUID,
        scheduleID: UUID,
        agentID: UUID,
        spaceID: UUID?
    ) throws -> IntentSchedule {
        let context = ModelContext(modelContainer)
        guard let intent = try context.fetch(FetchDescriptor<Intent>())
            .first(where: { $0.id == intentID }),
            intent.agentID == agentID, intent.spaceID == spaceID,
            intent.intentStatus == .active
        else {
            throw InitiativeError.inaccessibleIntent
        }
        guard let schedule = intent.schedules.first(where: { $0.id == scheduleID })
        else { throw InitiativeError.missingSchedule }
        return schedule
    }

    func list(agentID: UUID, spaceID: UUID?) throws -> [[String: String]] {
        let context = ModelContext(modelContainer)
        let intents = try context.fetch(FetchDescriptor<Intent>())
            .filter { $0.agentID == agentID && $0.spaceID == spaceID }
        return try context.fetch(FetchDescriptor<IntentInitiative>()).compactMap { agreement in
            guard let intent = intents.first(where: { $0.id == agreement.intentID }),
                  let schedule = intent.schedules.first(where: { $0.id == agreement.scheduleID })
            else { return nil }
            let active = agreement.enabled && intent.intentStatus == .active
            return [
                "id": agreement.id.uuidString, "intent_id": intent.id.uuidString,
                "schedule_id": schedule.id.uuidString, "instructions": agreement.instructions,
                "notification": agreement.notificationBody,
                "time": String(format: "%02d:%02d", schedule.hour ?? 9, schedule.minute ?? 0),
                "frequency": schedule.frequency.rawValue,
                "weekdays": (schedule.weekdays ?? []).map(String.init).joined(separator: ","),
                "status": active ?
                    (agreement.schedulingError == nil ? agreement
                        .registrationStatus : "registration_failed") : "disabled",
                "in_app": active ? "enabled" : "disabled",
                "error": agreement.schedulingError ?? "",
            ]
        }
    }

    /// Nearby times are suggestions only; no agreement changes until the user accepts.
    func nearbySuggestions(agentID: UUID, spaceID: UUID?) throws -> [[String: String]] {
        let agreements = try list(agentID: agentID, spaceID: spaceID)
            .filter { $0["status"] == "scheduled" }
        var suggestions: [[String: String]] = []
        for (index, first) in agreements.enumerated() {
            for second in agreements.dropFirst(index + 1) {
                guard let a = first["time"], let b = second["time"] else { continue }
                let aParts = a.split(separator: ":").compactMap { Int($0) }
                let bParts = b.split(separator: ":").compactMap { Int($0) }
                guard aParts.count == 2, bParts.count == 2 else { continue }
                let distance = abs(aParts[0] * 60 + aParts[1] - bParts[0] * 60 - bParts[1])
                let aDays = first["frequency"] == "daily" ? Set(1 ... 7) :
                    Set((first["weekdays"] ?? "").split(separator: ",").compactMap { Int($0) })
                let bDays = second["frequency"] == "daily" ? Set(1 ... 7) :
                    Set((second["weekdays"] ?? "").split(separator: ",").compactMap { Int($0) })
                guard distance > 0, distance <= 60, !aDays.isDisjoint(with: bDays) else { continue }
                suggestions.append([
                    "first_id": first["id"] ?? "",
                    "second_id": second["id"] ?? "",
                    "suggestion": "These initiatives at \(a) and \(b) overlap on some days. Ask whether the user wants one shared time; leave both unchanged until they agree.",
                ])
            }
        }
        return Array(suggestions.prefix(10))
    }

    /// Lifecycle writes may arrive during system I/O; repeat reconciliation after the current
    /// operation.
    func reconcile() async {
        guard !working else { reconcileAgain = true; return }
        working = true
        defer { finish() }
        do {
            try refreshWaiting()
            await cleanDeliveredNotifications()
            try await scheduler.reconcile(context: ModelContext(modelContainer))
        } catch { AppLogger.warning(
            "Initiative reconciliation failed: \(public: error.localizedDescription)",
            category: .backgroundPrompt
        ) }
    }

    func finish() {
        working = false
        if reconcileAgain {
            reconcileAgain = false
            Task { await self.reconcile() }
        }
    }
}
