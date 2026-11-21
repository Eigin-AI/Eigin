import Foundation

/// A proposed notification time or supported weekly repeating schedule.
struct NotificationSpacingSchedule {
    let id: UUID
    let timing: Timing

    static func sameTiming(_ first: IntentSchedule, _ second: IntentSchedule) -> Bool {
        guard let a = try? InitiativeRecurrenceCompiler.validate(first),
              let b = try? InitiativeRecurrenceCompiler.validate(second) else { return false }
        return a.0 == b.0 && a.1 == b.1 && a.2 == b.2
    }

    enum Timing {
        case once(Date)
        case recurring(IntentSchedule, timeZone: TimeZone? = nil)
    }
}

/// A nearby occurrence, without exposing another agent's message content.
struct NotificationSpacingWarning: Sendable {
    let proposedAt: Date
    let existingAt: Date
}

/// A hard collision prevents saving the proposed schedule.
struct NotificationSpacingConflict: Error {
    let occurrence: NotificationSpacingWarning
    var interval: TimeInterval = 300
}

/// Compares one-off and daily/weekly notifications with a strict minimum gap and an inclusive
/// warning window.
struct NotificationSpacingPolicy {
    var blockingInterval: TimeInterval = 5 * 60
    var warningInterval: TimeInterval = 15 * 60
    var calendar: Calendar = .current

    func validate(
        proposed: [NotificationSpacingSchedule],
        existing: [NotificationSpacingSchedule],
        now: Date
    ) throws -> [NotificationSpacingWarning] {
        let replacing = Set(proposed.map(\.id))
        var inventory = existing.filter { !replacing.contains($0.id) }
        var warnings: [NotificationSpacingWarning] = []
        for candidate in proposed {
            for other in inventory {
                guard let pair = closest(candidate.timing, other.timing, now: now) else { continue }
                let distance = abs(pair.proposedAt.timeIntervalSince(pair.existingAt))
                if distance < blockingInterval {
                    throw NotificationSpacingConflict(occurrence: pair, interval: blockingInterval)
                }
                if distance <= warningInterval { warnings.append(pair) }
            }
            inventory.append(candidate)
        }
        return warnings
    }

    private func closest(
        _ proposed: NotificationSpacingSchedule.Timing,
        _ existing: NotificationSpacingSchedule.Timing,
        now: Date
    ) -> NotificationSpacingWarning? {
        switch (proposed, existing) {
        case (.once(let a), .once(let b)):
            return NotificationSpacingWarning(proposedAt: a, existingAt: b)
        case (.once(let date), .recurring(let schedule, let zone)):
            return nearby(schedule, date: date, now: now, calendar: calendar(in: zone)).map {
                NotificationSpacingWarning(proposedAt: date, existingAt: $0)
            }
        case (.recurring(let schedule, let zone), .once(let date)):
            return nearby(schedule, date: date, now: now, calendar: calendar(in: zone)).map {
                NotificationSpacingWarning(proposedAt: $0, existingAt: date)
            }
        case (.recurring(let a, let aZone), .recurring(let b, let bZone)):
            let aCalendar = calendar(in: aZone)
            let bCalendar = calendar(in: bZone)
            // A full weekly cycle covers ordinary recurrence overlap. Transition weeks
            // cover elapsed-time collisions when the clock skips or repeats an hour.
            var anchors = [now]
            for zone in [aCalendar.timeZone, bCalendar.timeZone] {
                var cursor = now
                for _ in 0 ..< 2 {
                    guard let transition = zone.nextDaylightSavingTimeTransition(after: cursor)
                    else { break }
                    anchors.append(max(now, transition.addingTimeInterval(-86400)))
                    anchors.append(transition.addingTimeInterval(86400))
                    cursor = transition.addingTimeInterval(1)
                }
            }
            var pairs: [NotificationSpacingWarning] = []
            for anchor in anchors {
                guard let end = aCalendar.date(byAdding: .day, value: 8, to: anchor)
                else { continue }
                var cursor = anchor.addingTimeInterval(-1)
                while let date = a.nextOccurrence(onOrAfter: cursor, calendar: aCalendar),
                      date <= end
                {
                    if let other = nearby(b, date: date, now: now, calendar: bCalendar) {
                        pairs.append(NotificationSpacingWarning(
                            proposedAt: date,
                            existingAt: other
                        ))
                    }
                    cursor = date.addingTimeInterval(1)
                }
            }
            return pairs
                .min {
                    abs($0.proposedAt.timeIntervalSince($0.existingAt)) <
                        abs($1.proposedAt.timeIntervalSince($1.existingAt))
                }
        }
    }

    private func calendar(in zone: TimeZone?) -> Calendar {
        var result = calendar
        if let zone { result.timeZone = zone }
        return result
    }

    private func nearby(
        _ schedule: IntentSchedule,
        date: Date,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        // Resolve forward from each local day so repeated hours always use the first occurrence.
        let start = calendar.startOfDay(for: date)
        return (-1 ... 1).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let end = calendar.date(byAdding: .day, value: 1, to: day),
                  let occurrence = schedule.nextOccurrence(
                      onOrAfter: day.addingTimeInterval(-1),
                      calendar: calendar
                  ),
                  occurrence < end, occurrence >= now else { return nil }
            return occurrence
        }.min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }
    }
}
