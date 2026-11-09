import Foundation

/// Compiles daily and weekly initiatives into disjoint repeating notification patterns.
enum InitiativeRecurrenceCompiler {
    /// Validates the entire desired set before producing any registration changes.
    static func compile(
        _ initiatives: [InitiativeSchedule],
        availableRequestCount: Int
    ) throws -> [InitiativeNotificationPattern] {
        guard availableRequestCount >= 0 else {
            throw InitiativeScheduleError.invalidRequestBudget
        }
        guard Set(initiatives.map(\.initiativeID)).count == initiatives.count else {
            throw InitiativeScheduleError.duplicateInitiative
        }

        var groups: [Group: [Int: Set<UUID>]] = [:]
        for initiative in initiatives {
            let days = try weekdays(for: initiative.schedule)
            guard let hour = initiative.schedule.hour,
                  let minute = initiative.schedule.minute
            else {
                throw InitiativeScheduleError.explicitTimeRequired
            }
            guard (0 ... 23).contains(hour), (0 ... 59).contains(minute) else {
                throw InitiativeScheduleError.invalidTime
            }
            let group = Group(
                initiativeID: initiative.initiativeID,
                agentID: initiative.agentID,
                spaceID: initiative.spaceID,
                hour: hour,
                minute: minute
            )
            for day in days {
                groups[group, default: [:]][day, default: []].insert(initiative.initiativeID)
            }
        }

        var patterns: [InitiativeNotificationPattern] = []
        for group in groups.keys.sorted(by: { $0.sortKey < $1.sortKey }) {
            guard let days = groups[group] else { continue }
            if let members = days[1], (1 ... 7).allSatisfy({ days[$0] == members }) {
                patterns.append(group.pattern(weekday: nil, members: members))
            } else {
                for day in 1 ... 7 {
                    guard let members = days[day] else { continue }
                    patterns.append(group.pattern(weekday: day, members: members))
                }
            }
        }
        guard patterns.count <= availableRequestCount else {
            throw InitiativeScheduleError.capacityExceeded(
                required: patterns.count, available: availableRequestCount
            )
        }
        return patterns
    }

    private static func weekdays(for schedule: IntentSchedule) throws -> Set<Int> {
        switch schedule.frequency {
        case .daily:
            Set(1 ... 7)
        case .weekly:
            try validatedWeekdays(schedule.weekdays)
        case .monthly:
            throw InitiativeScheduleError.unsupportedMonthlySchedule
        }
    }

    private static func validatedWeekdays(_ weekdays: [Int]?) throws -> Set<Int> {
        guard let weekdays, !weekdays.isEmpty,
              weekdays.allSatisfy({ (1 ... 7).contains($0) })
        else {
            throw InitiativeScheduleError.invalidWeekdays
        }
        return Set(weekdays)
    }

    private struct Group: Hashable {
        let initiativeID: UUID
        let agentID: UUID
        let spaceID: UUID?
        let hour: Int
        let minute: Int

        var sortKey: String {
            "\(initiativeID.uuidString)/\(agentID.uuidString)/\(spaceID?.uuidString ?? "global")/\(hour)/\(minute)"
        }

        func pattern(weekday: Int?, members: Set<UUID>) -> InitiativeNotificationPattern {
            InitiativeNotificationPattern(
                agentID: agentID,
                spaceID: spaceID,
                hour: hour,
                minute: minute,
                weekday: weekday,
                initiativeIDs: members.sorted { $0.uuidString < $1.uuidString }
            )
        }
    }
}
