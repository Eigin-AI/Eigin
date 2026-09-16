import Foundation

/// A recurring temporal trigger attached to an ``Intent``.
///
/// Schedules express routines — "log sleep every morning", "garden on weekends",
/// "pay rent on the 1st". As an occurrence approaches, the intent's relevance
/// rises so the agent raises the intent at the right moment (see ``IntentRelevance``).
struct IntentSchedule: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var content: String
    var frequency: ScheduleFrequency
    /// For ``ScheduleFrequency/weekly``: weekdays the schedule fires on, using
    /// `Calendar`'s convention (1 = Sunday … 7 = Saturday). Ignored otherwise.
    var weekdays: [Int]?
    /// For ``ScheduleFrequency/monthly``: days of the month (1…31). A day that
    /// doesn't exist in a given month (e.g. 31 in February) is simply skipped.
    var monthDays: [Int]?
    /// Hour of day (0…23). Defaults to ``defaultHour`` when nil.
    var hour: Int?
    /// Minute of hour (0…59). Defaults to 0 when nil.
    var minute: Int?

    init(
        id: UUID = UUID(),
        content: String,
        frequency: ScheduleFrequency,
        weekdays: [Int]? = nil,
        monthDays: [Int]? = nil,
        hour: Int? = nil,
        minute: Int? = nil
    ) {
        self.id = id
        self.content = content
        self.frequency = frequency
        self.weekdays = weekdays
        self.monthDays = monthDays
        self.hour = hour
        self.minute = minute
    }

    /// Time-of-day used when no explicit hour is given — a neutral mid-morning.
    static let defaultHour = 9

    /// The first occurrence at or after `date`, or nil if the schedule is
    /// malformed (e.g. weekly with no weekdays).
    func nextOccurrence(onOrAfter date: Date, calendar: Calendar = .current) -> Date? {
        occurrence(from: date, direction: .forward, calendar: calendar)
    }

    /// The most recent occurrence at or before `date`, or nil if none/malformed.
    func lastOccurrence(onOrBefore date: Date, calendar: Calendar = .current) -> Date? {
        occurrence(from: date, direction: .backward, calendar: calendar)
    }

    private func occurrence(
        from date: Date,
        direction: Calendar.SearchDirection,
        calendar: Calendar
    ) -> Date? {
        let components = matchingComponents()
        guard !components.isEmpty else { return nil }
        let policy: Calendar.MatchingPolicy = frequency == .monthly ? .strict : .nextTime
        let candidates = components.compactMap {
            calendar.nextDate(
                after: date,
                matching: $0,
                matchingPolicy: policy,
                direction: direction
            )
        }
        // Closest to `date` in the requested direction.
        return direction == .forward ? candidates.min() : candidates.max()
    }

    /// The set of `DateComponents` patterns this schedule fires on.
    private func matchingComponents() -> [DateComponents] {
        let h = hour ?? Self.defaultHour
        let m = minute ?? 0
        switch frequency {
        case .daily:
            return [DateComponents(hour: h, minute: m)]
        case .weekly:
            return (weekdays ?? []).map { DateComponents(hour: h, minute: m, weekday: $0) }
        case .monthly:
            return (monthDays ?? []).map { DateComponents(day: $0, hour: h, minute: m) }
        }
    }
}

/// How often an ``IntentSchedule`` recurs.
enum ScheduleFrequency: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
}
