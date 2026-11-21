import Foundation
import SwiftData

/// Reads outstanding notification reservations without suspending before a caller's save.
@MainActor struct NotificationSpacingValidator {
    let container: ModelContainer
    var policy = NotificationSpacingPolicy()

    func validate(date: Date, now: Date = .now) throws -> [NotificationSpacingWarning] {
        try validate(
            proposed: [NotificationSpacingSchedule(id: UUID(), timing: .once(date))],
            context: ModelContext(container), now: now
        )
    }

    func validate(
        proposed: [NotificationSpacingSchedule],
        context: ModelContext,
        now: Date = .now
    ) throws -> [NotificationSpacingWarning] {
        guard !proposed.isEmpty else { return [] }
        let agents = try Set(context.fetch(FetchDescriptor<Agent>()).map(\.id))
        let spaces = try context.fetch(FetchDescriptor<Space>())
        func validScope(agentID: UUID, spaceID: UUID?) -> Bool {
            agents
                .contains(agentID) &&
                (spaceID == nil || spaces.contains { $0.id == spaceID && $0.agentID == agentID })
        }
        var existing: [NotificationSpacingSchedule] = try context
            .fetch(FetchDescriptor<AgentInitiativeRequest>()).compactMap { request in
                guard request.handledAt == nil, request.disposition == nil,
                      validScope(agentID: request.agentID, spaceID: request.spaceID),
                      let date = request.dueAt, date >= now else { return nil }
                return NotificationSpacingSchedule(id: request.id, timing: .once(date))
            }
        let intents = try context.fetch(FetchDescriptor<Intent>())
        for agreement in try context.fetch(FetchDescriptor<IntentInitiative>()) {
            guard agreement.enabled,
                  let intent = intents.first(where: { $0.id == agreement.intentID }),
                  intent.intentStatus == .active,
                  validScope(agentID: intent.agentID, spaceID: intent.spaceID),
                  let schedule = intent.schedules.first(where: { $0.id == agreement.scheduleID }),
                  (try? InitiativeRecurrenceCompiler.validate(schedule)) != nil else { continue }
            existing.append(NotificationSpacingSchedule(
                id: agreement.id,
                timing: .recurring(schedule)
            ))
        }
        // Active snapshots reserve installed times until reconciliation replaces them.
        let activeIDs = Set(existing.map(\.id))
        for registration in try context.fetch(FetchDescriptor<InitiativeRegistration>())
            where registration.retiredAt == nil
        {
            let delivery = try JSONDecoder().decode(
                InitiativeDelivery.self,
                from: registration.payload
            )
            let zone = delivery.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? policy
                .calendar.timeZone
            for member in delivery.members where activeIDs.contains(member.initiativeID) {
                guard (try? InitiativeRecurrenceCompiler.validate(member.schedule)) != nil
                else { continue }
                let alreadyReserved = existing.contains { reservation in
                    guard reservation.id == member.initiativeID,
                          case .recurring(let schedule, let reservedZone) = reservation.timing
                    else { return false }
                    return (reservedZone ?? policy.calendar.timeZone) == zone &&
                        NotificationSpacingSchedule.sameTiming(
                            schedule,
                            member.schedule
                        )
                }
                guard !alreadyReserved else { continue }
                existing.append(NotificationSpacingSchedule(
                    id: member.initiativeID,
                    timing: .recurring(member.schedule, timeZone: zone)
                ))
            }
        }
        return try policy.validate(proposed: proposed, existing: existing, now: now)
    }
}
