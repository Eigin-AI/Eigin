import CryptoKit
import Foundation
import SwiftData
import UserNotifications

/// System boundary for reconciling this app's pending notifications.
@MainActor protocol InitiativeNotificationAccess {
    func pending() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func remove(_ identifiers: [String])
}

@MainActor struct SystemInitiativeNotifications: InitiativeNotificationAccess {
    func pending() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func remove(_ identifiers: [String]) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// Snapshot of exactly what a delivered initiative offered to run.
struct InitiativeDelivery: Codable, Equatable {
    struct Member: Codable, Equatable {
        let initiativeID: UUID
        let intentID: UUID
        let schedule: IntentSchedule
        let instructions: String
        let body: String
        let revision: Date
    }

    let agentID: UUID
    let spaceID: UUID?
    let hour: Int
    let minute: Int
    let weekday: Int?
    let members: [Member]

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    var body: String {
        members.map(\.body).joined(separator: "\n")
    }
}

/// Registers a complete set of repeating requests, retaining immutable routing snapshots.
@MainActor final class InitiativeNotificationScheduler {
    static let prefix = "intent-initiative-"
    static let registrationIDKey = "scheduledInitiativeID"
    let notifications: any InitiativeNotificationAccess
    let authorization: any NotificationAuthorizationAccess
    let contentPreparer: any CommunicationNotificationPreparing

    init(
        notifications: any InitiativeNotificationAccess = SystemInitiativeNotifications(),
        authorization: any NotificationAuthorizationAccess = SystemNotificationAuthorization(),
        contentPreparer: any CommunicationNotificationPreparing =
            SystemCommunicationNotificationPreparer()
    ) {
        self.notifications = notifications
        self.authorization = authorization
        self.contentPreparer = contentPreparer
    }

    func compile(
        context: ModelContext,
        otherRequestCount: Int,
        strict: Bool = true
    ) throws -> [InitiativeDelivery] {
        let intents = try Dictionary(uniqueKeysWithValues: context.fetch(FetchDescriptor<Intent>())
            .map { (
                $0.id,
                $0
            ) })
        let agreements = try context.fetch(FetchDescriptor<IntentInitiative>()).filter(\.enabled)
        let agents = try Set(context.fetch(FetchDescriptor<Agent>()).map(\.id))
        let spaces = try context.fetch(FetchDescriptor<Space>())
        var members: [UUID: InitiativeDelivery.Member] = [:]
        let schedules: [InitiativeSchedule] = try agreements.compactMap { agreement in
            guard let intent = intents[agreement.intentID], intent.intentStatus == .active,
                  let schedule = intent.schedules.first(where: { $0.id == agreement.scheduleID }),
                  agents.contains(intent.agentID),
                  intent.spaceID == nil || spaces
                  .contains(where: { $0.id == intent.spaceID && $0.agentID == intent.agentID })
            else {
                agreement.schedulingError = InitiativeError.inaccessibleIntent.localizedDescription
                return nil
            }
            let input = InitiativeSchedule(
                initiativeID: agreement.id,
                intentID: intent.id,
                agentID: intent.agentID,
                spaceID: intent.spaceID,
                schedule: schedule
            )
            do { _ = try InitiativeRecurrenceCompiler.compile([input], availableRequestCount: 7) }
            catch {
                if strict { throw error }
                agreement.schedulingError = error.localizedDescription
                return nil
            }
            members[agreement.id] = .init(
                initiativeID: agreement.id, intentID: intent.id, schedule: schedule,
                instructions: agreement.instructions, body: agreement.notificationBody,
                revision: agreement.updatedAt
            )
            return InitiativeSchedule(
                initiativeID: agreement.id, intentID: intent.id, agentID: intent.agentID,
                spaceID: intent.spaceID, schedule: schedule
            )
        }
        // Leave four slots for one-off follow-ups and other app notifications.
        let patterns = try InitiativeRecurrenceCompiler.compile(
            schedules,
            availableRequestCount: max(0, 60 - otherRequestCount)
        )
        return patterns.map { pattern in
            InitiativeDelivery(
                agentID: pattern.agentID, spaceID: pattern.spaceID,
                hour: pattern.hour, minute: pattern.minute, weekday: pattern.weekday,
                members: pattern.initiativeIDs.compactMap { members[$0] }
            )
        }
    }

    func reconcile(context: ModelContext) async throws {
        let pending = await notifications.pending()
        let owned = pending.filter { $0.identifier.hasPrefix(Self.prefix) }
        let agreements = try context.fetch(FetchDescriptor<IntentInitiative>())
        // Remove only obsolete agreements; a failed replacement must not cancel unrelated work.
        let invalid = owned.filter { (try? InitiativeConversationService.validatedDelivery(
            registrationID: $0.identifier,
            context: context
        )) == nil }
        notifications.remove(invalid.map(\.identifier))
        do {
            let deliveries = try compile(
                context: context,
                otherRequestCount: pending.count - owned.count,
                strict: false
            )
            let authorized = await NotificationPermission.requestIfNeeded(
                canPromptUser: false,
                authorization: authorization
            )
            if !deliveries.isEmpty, !authorized {
                notifications.remove(owned.map(\.identifier))
                throw InitiativeError.permissionRequired
            }
            var desired: [String: InitiativeDelivery] = [:]
            let registrations = try context.fetch(FetchDescriptor<InitiativeRegistration>())
            for delivery in deliveries {
                let data = try delivery.encoded()
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let id = Self.prefix + digest
                desired[id] = delivery
                if let existing = registrations.first(where: { $0.id == id }) {
                    existing.retiredAt = nil
                } else {
                    context.insert(InitiativeRegistration(id: id, payload: data))
                }
            }
            for registration in registrations where desired[registration.id] == nil {
                registration.retiredAt = registration.retiredAt ?? .now
            }
            try context.save()
            notifications.remove(owned.map(\.identifier).filter { desired[$0] == nil })
            // Replace plain requests in place without changing their routing snapshots.
            let installed = Set(owned.filter {
                $0.content.categoryIdentifier == CommunicationNotificationContent.categoryIdentifier
            }.map(\.identifier)).subtracting(invalid.map(\.identifier))
            let agents = try Dictionary(uniqueKeysWithValues: context
                .fetch(FetchDescriptor<Agent>()).map { (
                    $0.id,
                    $0
                ) })
            var failed = false
            for (id, delivery) in desired where !installed.contains(id) {
                guard let agent = agents[delivery.agentID] else { failed = true; continue }
                let content = UNMutableNotificationContent()
                content.title = agent.name
                content.body = delivery.body
                content.sound = .default
                content.categoryIdentifier = CommunicationNotificationContent.categoryIdentifier
                content.userInfo = [Self.registrationIDKey: id]
                let prepared = await contentPreparer.prepare(
                    content, agentName: agent.name, agentEmoji: agent.emoji,
                    agentID: agent.id, conversationID: id
                )
                let components = DateComponents(
                    hour: delivery.hour,
                    minute: delivery.minute, second: 0, weekday: delivery.weekday
                )
                do { try await notifications.add(UNNotificationRequest(
                    identifier: id, content: prepared,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                )) } catch { failed = true }
            }
            let actual = await Set(notifications.pending().map(\.identifier))
            failed = failed || Set(desired.keys) != Set(actual.filter { $0.hasPrefix(Self.prefix) })
            for registration in registrations {
                if let retired = registration.retiredAt,
                   retired < Date.now.addingTimeInterval(-90 * 86400)
                {
                    context.delete(registration)
                }
            }
            for agreement in agreements {
                let required = desired
                    .filter { $0.value.members.contains { $0.initiativeID == agreement.id } }
                    .map(\.key)
                if !required.isEmpty {
                    let installed = Set(required).isSubset(of: actual)
                    agreement.registrationStatus = installed ? "scheduled" : "pending"
                    agreement.schedulingError = installed ? nil : InitiativeError.registrationFailed
                        .localizedDescription
                }
            }
            try context.save()
            if failed { throw InitiativeError.registrationFailed }
        } catch {
            let actual = await Set(notifications.pending().map(\.identifier))
            let registrations = (try? context.fetch(FetchDescriptor<InitiativeRegistration>())) ??
                []
            let installedMembers = Set(registrations.filter { actual.contains($0.id) }.flatMap {
                (try? JSONDecoder().decode(InitiativeDelivery.self, from: $0.payload).members
                    .map(\.initiativeID)) ?? []
            })
            for agreement in agreements
                where agreement.enabled && !installedMembers.contains(agreement.id)
            {
                agreement.schedulingError = agreement.schedulingError ?? error.localizedDescription
            }
            try context.save()
            throw error
        }
    }
}
