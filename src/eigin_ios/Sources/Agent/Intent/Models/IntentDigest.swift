import Foundation

/// Produces short, human-readable cues about an intent's current temporal state
/// — "due today", "in 3 days", "2 open tasks" — for surfacing in prompts and
/// hints so the agent knows *why* an intent is rising right now.
enum IntentDigest {
    /// Compact cues, ordered most-pressing first. Empty when nothing is timely.
    static func cues(for intent: IntentSnapshot, at now: Date = .now) -> [String] {
        var cues: [String] = []

        if let schedule = scheduleCue(intent.schedules, at: now) {
            cues.append(schedule)
        }
        if let event = eventCue(intent.events, at: now) {
            cues.append(event)
        }
        let open = intent.tasks.count { !$0.completed }
        if open > 0 {
            cues.append("\(open) open task\(open == 1 ? "" : "s")")
        }
        return cues
    }

    /// The cues joined into a single parenthetical-ready string, or nil.
    static func summary(for intent: IntentSnapshot, at now: Date = .now) -> String? {
        let cues = cues(for: intent, at: now)
        return cues.isEmpty ? nil : cues.joined(separator: ", ")
    }

    // MARK: - Private

    private static func scheduleCue(_ schedules: [IntentSchedule], at now: Date) -> String? {
        let calendar = Calendar.current
        for schedule in schedules {
            guard let next = schedule.nextOccurrence(onOrAfter: now) else { continue }
            switch dayOffset(from: now, to: next, calendar: calendar) {
            case 0: return "scheduled today"
            case 1: return "scheduled tomorrow"
            default: break
            }
        }
        // A daily/weekly slot that already fired earlier today.
        for schedule in schedules {
            if let last = schedule.lastOccurrence(onOrBefore: now),
               dayOffset(from: now, to: last, calendar: calendar) == 0 { return "scheduled today" }
        }
        return nil
    }

    /// Whole-calendar-day difference between two instants, relative to `from`.
    private static func dayOffset(from: Date, to: Date, calendar: Calendar) -> Int {
        let fromDay = calendar.startOfDay(for: from)
        let toDay = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: fromDay, to: toDay).day ?? 0
    }

    private static func eventCue(_ events: [IntentEvent], at now: Date) -> String? {
        let upcoming = events
            .filter { $0.at >= now }
            .min { $0.at < $1.at }
        guard let event = upcoming else { return nil }
        let days = Calendar.current.dateComponents([.day], from: now, to: event.at).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        default: return "in \(days) days"
        }
    }
}
