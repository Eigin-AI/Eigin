import Foundation

/// Computes how relevant an intent is *right now*.
///
/// Relevance is a weighted blend of continuous signals rather than strict tiers,
/// so every factor contributes: a due schedule or an approaching event lifts an
/// intent to the top, but recency still separates otherwise-equal intents and an
/// intent with open tasks edges ahead of one that's fully done. Nothing is ever
/// zeroed out by the presence of another signal — the strongest mix wins.
///
/// Both temporal signals share one asymmetric bell shape (see ``bell(offset:lead:trail:)``)
/// at different timescales — schedules ramp over hours, events over days.
///
/// Output is an unbounded score used only for ordering; callers sort descending.
enum IntentRelevance {
    // MARK: Tunable weights (temporal signals dominate)

    static let scheduleWeight = 1.0
    static let eventWeight = 1.0
    static let taskWeight = 0.5
    static let recencyWeight = 0.3

    // MARK: Tunable shapes — asymmetric bell per timescale

    // Schedule (clock time): ~1-day lead, ~couple-hour trail.
    static let scheduleLead: TimeInterval = 8 * 3600
    static let scheduleTrail: TimeInterval = 2 * 3600
    // Event (calendar time): ~1-week ramp, ~2-day tail.
    static let eventLead: TimeInterval = 3.5 * 86400
    static let eventTrail: TimeInterval = 1.5 * 86400

    /// How quickly an open task's due date pulls as it nears.
    static let taskDueFalloffDays = 3.0
    /// Recency time constant — fresh intents lift, fading gently over ~2 weeks.
    static let recencyFalloffDays = 14.0

    /// Asymmetric bell: gentle S-curve ramp as `offset` approaches 0 from above
    /// (approaching, width `lead`), shorter decay as it goes below 0 (receding,
    /// width `trail`). Peaks at 1.0 at offset 0. Never hard-zeroes. Unit
    /// agnostic — offset, lead, and trail share one unit.
    ///
    /// `offset` = peak − value (positive = upcoming, negative = past).
    static func bell(offset: Double, lead: Double, trail: Double) -> Double {
        let sigma = offset >= 0 ? lead : trail
        return exp(-(offset * offset) / (2 * sigma * sigma))
    }

    /// `bell` for clock time — all values in seconds (`TimeInterval`), with
    /// `offset` = peak date − now. Future peak (positive offset) uses `lead`,
    /// past peak uses `trail`.
    static func timeBell(offset: TimeInterval, lead: TimeInterval, trail: TimeInterval) -> Double {
        bell(offset: offset, lead: lead, trail: trail)
    }

    /// Blended relevance score for a snapshot at the given instant.
    static func relevance(for intent: IntentSnapshot, at now: Date = .now) -> Double {
        scheduleWeight * scheduleSignal(intent.schedules, at: now)
            + eventWeight * eventSignal(intent.events, at: now)
            + taskWeight * taskSignal(intent.tasks, at: now)
            + recencyWeight * recencySignal(intent.updatedAt, at: now)
    }

    // MARK: Signals (each ~0…1)

    /// Peaks when a schedule is about to fire, dropping fast once it has passed.
    private static func scheduleSignal(_ schedules: [IntentSchedule], at now: Date) -> Double {
        schedules.map { schedule in
            let offsets = [
                schedule.nextOccurrence(onOrAfter: now),
                schedule.lastOccurrence(onOrBefore: now),
            ]
            .compactMap { $0?.timeIntervalSince(now) }
            guard let nearest = offsets.min(by: { abs($0) < abs($1) }) else { return 0 }
            return timeBell(offset: nearest, lead: scheduleLead, trail: scheduleTrail)
        }
        .max() ?? 0
    }

    /// Rises smoothly toward the event, then fades over a day or two.
    private static func eventSignal(_ events: [IntentEvent], at now: Date) -> Double {
        events.map { event in
            timeBell(
                offset: event.at.timeIntervalSince(now),
                lead: eventLead,
                trail: eventTrail
            )
        }
        .max() ?? 0
    }

    /// Positive while incomplete tasks remain; lifted by near or overdue dates.
    /// Zero when there are no tasks or all are complete.
    private static func taskSignal(_ tasks: [IntentTask], at now: Date) -> Double {
        let open = tasks.filter { !$0.completed }
        guard !open.isEmpty else { return 0 }
        let dueProximity = open.compactMap { task -> Double? in
            guard let due = task.due else { return nil }
            let days = due.timeIntervalSince(now) / 86400
            if days <= 0 { return 1 } // due or overdue
            return exp(-days / taskDueFalloffDays)
        }
        .max() ?? 0
        return 0.5 + 0.5 * dueProximity
    }

    /// Gentle, always-present lift from how recently the intent was touched.
    private static func recencySignal(_ updatedAt: Date, at now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(updatedAt) / 86400)
        return exp(-days / recencyFalloffDays)
    }
}
