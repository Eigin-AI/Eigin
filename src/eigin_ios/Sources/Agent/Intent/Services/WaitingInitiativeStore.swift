import CryptoKit
import Foundation
import SwiftData

/// Discovers due invitations without consulting notification delivery or authorization.
@MainActor enum WaitingInitiativeStore {
    static func registrationID(for delivery: InitiativeDelivery) throws -> String {
        try InitiativeNotificationScheduler.prefix + digest(delivery.encoded())
    }

    static func revision(for delivery: InitiativeDelivery) throws -> String {
        // Weekday-specific requests for one agreement share one occurrence identity.
        let normalized = InitiativeDelivery(
            identityVersion: 2, agentID: delivery.agentID, spaceID: delivery.spaceID,
            hour: delivery.hour, minute: delivery.minute, weekday: nil, members: delivery.members
        )
        return try digest(normalized.encoded())
    }

    static func occurrenceID(
        member: InitiativeDelivery.Member,
        revision: String,
        dueAt: Date
    ) -> String {
        "\(member.initiativeID.uuidString):\(revision):\(Int64(dueAt.timeIntervalSince1970))"
    }

    /// Returns the scheduled instant, including an occurrence exactly at the supplied time.
    static func latest(_ schedule: IntentSchedule, at date: Date, calendar: Calendar) -> Date? {
        guard let candidate = schedule.lastOccurrence(
            onOrBefore: date.addingTimeInterval(1),
            calendar: calendar
        )
        else { return nil }
        // Backward calendar searches select the second repeated hour at the DST boundary.
        let dayStart = calendar.startOfDay(for: candidate).addingTimeInterval(-1)
        return schedule.nextOccurrence(onOrAfter: dayStart, calendar: calendar)
    }

    /// Installed requests retain their scheduling zone until foreground reconciliation replaces
    /// them.
    static func notificationOccurrenceID(
        delivery: InitiativeDelivery,
        deliveredAt: Date,
        calendar: Calendar = .current
    ) throws -> String {
        guard delivery.identityVersion == 2, delivery.members.count == 1,
              let member = delivery.members.first else { throw InitiativeError.staleNotification }
        var scheduledCalendar = calendar
        if let zone = delivery.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) {
            scheduledCalendar.timeZone = zone
        }
        guard let due = latest(member.schedule, at: deliveredAt, calendar: scheduledCalendar) else {
            throw InitiativeError.staleNotification
        }
        return try occurrenceID(member: member, revision: revision(for: delivery), dueAt: due)
    }

    /// Saves discovery, high-water marks, supersession, and retention together.
    @discardableResult
    static func reconcile(
        context: ModelContext, now: Date = .now, calendar: Calendar = .current
    ) throws -> Date? {
        do {
            let deliveries = try InitiativeNotificationScheduler().compile(
                context: context, otherRequestCount: 0, strict: false, enforceCapacity: false,
                calendar: calendar
            )
            var cursors = try context.fetch(FetchDescriptor<InitiativeCursor>())
            var waiting = try context.fetch(FetchDescriptor<WaitingInitiative>())
            var registrations = try context.fetch(FetchDescriptor<InitiativeRegistration>())
            let claimed = try Set(context.fetch(FetchDescriptor<InitiativeOccurrence>()).map(\.id))
            var revisions: [UUID: String] = [:]
            var nextDue: Date?
            for delivery in deliveries {
                guard let member = delivery.members.first,
                      revisions[member.initiativeID] == nil else { continue }
                let revision = try revision(for: delivery)
                revisions[member.initiativeID] = revision
                if let next = member.schedule.nextOccurrence(onOrAfter: now, calendar: calendar) {
                    nextDue = min(nextDue ?? next, next)
                }
                let cursor: InitiativeCursor
                if let existing = cursors.first(where: { $0.initiativeID == member.initiativeID }) {
                    cursor = existing
                    if cursor.revision != revision {
                        cursor.revision = revision
                        cursor.evaluatedThrough = max(cursor.evaluatedThrough, now)
                    }
                } else {
                    cursor = InitiativeCursor(
                        initiativeID: member.initiativeID,
                        revision: revision,
                        evaluatedThrough: now,
                        timeZoneIdentifier: calendar.timeZone.identifier
                    )
                    context.insert(cursor)
                    cursors.append(cursor)
                }
                var elapsedCalendar = calendar
                elapsedCalendar
                    .timeZone = TimeZone(identifier: cursor.timeZoneIdentifier) ?? calendar.timeZone
                cursor.timeZoneIdentifier = calendar.timeZone.identifier
                guard now > cursor.evaluatedThrough else { continue }
                let previous = cursor.evaluatedThrough
                cursor.evaluatedThrough = now
                guard let due = latest(member.schedule, at: now, calendar: elapsedCalendar),
                      due > previous, due <= now else { continue }
                for item in waiting
                    where item.initiativeID == member.initiativeID
                {
                    context.delete(item)
                }
                waiting.removeAll { $0.initiativeID == member.initiativeID }
                let id = occurrenceID(member: member, revision: revision, dueAt: due)
                guard !claimed.contains(id) else { continue }
                // Store the matching weekday snapshot, even when notification delivery is disabled.
                var snapshot = deliveries.first {
                    $0.members.first?.initiativeID == member.initiativeID &&
                        ($0.weekday == nil || $0.weekday == elapsedCalendar.component(
                            .weekday,
                            from: due
                        ))
                } ?? delivery
                snapshot.timeZoneIdentifier = elapsedCalendar.timeZone.identifier
                let registrationID = try registrationID(for: snapshot)
                if !registrations.contains(where: { $0.id == registrationID }) {
                    let registration = try InitiativeRegistration(
                        id: registrationID,
                        payload: snapshot.encoded()
                    )
                    context.insert(registration)
                    registrations.append(registration)
                }
                let item = WaitingInitiative(
                    id: id,
                    initiativeID: member.initiativeID,
                    revision: revision,
                    agentID: delivery.agentID,
                    spaceID: delivery.spaceID,
                    dueAt: due,
                    registrationID: registrationID,
                    body: member.body
                )
                context.insert(item)
                waiting.append(item)
            }
            for cursor in cursors where revisions[cursor.initiativeID] == nil {
                // Keep the high-water mark through disable/re-enable and clock rollback.
                cursor.evaluatedThrough = max(cursor.evaluatedThrough, now)
            }
            for item in waiting.sorted(by: newestFirst) {
                guard revisions[item.initiativeID] == item.revision, !claimed.contains(item.id)
                else {
                    context.delete(item)
                    continue
                }
            }
            if let followUpDue = try WaitingMessageStore.retain(context: context, now: now) {
                nextDue = min(nextDue ?? followUpDue, followUpDue)
            }
            try context.save()
            return nextDue
        } catch {
            context.rollback()
            throw error
        }
    }

    static func newestFirst(_ a: WaitingInitiative, _ b: WaitingInitiative) -> Bool {
        a.dueAt == b.dueAt ? a.id < b.id : a.dueAt > b.dueAt
    }

    static func dismiss(id: String, context: ModelContext) throws {
        guard let item = try context.fetch(FetchDescriptor<WaitingInitiative>())
            .first(where: { $0.id == id })
        else { return }
        context.delete(item)
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// Claims the normal chat and removes the invitation in one save.
    static func open(id: String, context: ModelContext) throws -> UUID {
        if let claim = try context.fetch(FetchDescriptor<InitiativeOccurrence>())
            .first(where: { $0.id == id })
        {
            guard try context.fetch(FetchDescriptor<Chat>())
                .contains(where: { $0.id == claim.chatID })
            else { throw InitiativeError.missingChat }
            return claim.chatID
        }
        guard let item = try context.fetch(FetchDescriptor<WaitingInitiative>())
            .first(where: { $0.id == id })
        else { throw InitiativeError.staleNotification }
        let delivery = try InitiativeConversationService.validatedDelivery(
            registrationID: item.registrationID,
            context: context
        )
        let chat = Chat(agentID: item.agentID, spaceID: item.spaceID)
        context.insert(chat)
        context.insert(InitiativeOccurrence(
            id: item.id,
            registrationID: item.registrationID,
            deliveredAt: item.dueAt,
            chatID: chat.id,
            intentIDs: delivery.members.map(\.intentID)
        ))
        context.delete(item)
        do { try context.save() } catch { context.rollback(); throw error }
        return chat.id
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
