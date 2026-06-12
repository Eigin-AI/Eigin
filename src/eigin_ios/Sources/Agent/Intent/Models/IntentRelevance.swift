import Foundation

/// Computes how relevant an intent is *right now*, replacing the old decay model.
///
/// Relevance is a weighted blend of continuous signals rather than strict tiers,
/// so every factor contributes: a due schedule or an approaching event lifts an
/// intent to the top, but recency still separates otherwise-equal intents and an
/// intent with open tasks edges ahead of one that's fully done. Nothing is ever
/// zeroed out by the presence of another signal — the strongest mix wins.
///
/// Output is an unbounded score used only for ordering; callers sort descending.
enum IntentRelevance {
    // MARK: Tunable weights (temporal signals dominate)

    static let scheduleWeight = 1.0
    static let eventWeight = 1.0
    static let taskWeight = 0.5
    static let recencyWeight = 0.3

    // MARK: Tunable shapes

    /// How quickly a schedule's pull falls off either side of its occurrence.
    /// At ~8h from the firing time the signal is ~0.37, so a daily reminder is
    /// strong around its time and faint by the next day.
    static let scheduleFalloffHours = 8.0
    /// How many days ahead an event starts pulling, ramping to full at the date.
    static let eventWindowDays = 7.0
    /// How quickly an open task's due date pulls as it nears.
    static let taskDueFalloffDays = 3.0
    /// Recency time constant — fresh intents lift, fading gently over ~2 weeks.
    static let recencyFalloffDays = 14.0

    /// Blended relevance score for a snapshot at the given instant.
    static func relevance(for intent: IntentSnapshot, at now: Date = .now) -> Double {
        scheduleWeight * scheduleSignal(intent.schedules, at: now)
            + eventWeight * eventSignal(intent.events, at: now)
            + taskWeight * taskSignal(intent.tasks, at: now)
            + recencyWeight * recencySignal(intent.updatedAt, at: now)
    }

    // MARK: Signals (each ~0…1)

    /// Peaks when any schedule is firing now, tapering on both sides.
    private static func scheduleSignal(_ schedules: [IntentSchedule], at now: Date) -> Double {
        schedules.map { schedule in
            let distances = [
                schedule.nextOccurrence(onOrAfter: now),
                schedule.lastOccurrence(onOrBefore: now),
            ]
            .compactMap { $0.map { abs($0.timeIntervalSince(now)) } }
            guard let nearest = distances.min() else { return 0 }
            return exp(-(nearest / 3600) / scheduleFalloffHours)
        }
        .max() ?? 0
    }

    /// Rises as the nearest upcoming event approaches within the window.
    private static func eventSignal(_ events: [IntentEvent], at now: Date) -> Double {
        events.map { event in
            let days = event.at.timeIntervalSince(now) / 86400
            guard days >= 0, days <= eventWindowDays else { return 0 }
            return 1 - days / eventWindowDays
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
