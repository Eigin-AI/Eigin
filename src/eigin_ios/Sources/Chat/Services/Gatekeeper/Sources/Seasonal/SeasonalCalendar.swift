import Foundation

/// A seasonal moment for a region — a window of the year (a holiday, a break)
/// paired with the hint prompt that primes the agent to speak into it.
///
/// The window logic lives here in Swift; the prose lives in
/// `design/prompts/hints/seasonal/` and is referenced through the generated
/// ``Prompt`` accessors.
struct SeasonalMoment {
    /// Stable identifier, handy for tests and logging (e.g. `"summer_holiday"`).
    let id: String
    /// Agent-facing hint prompt for this moment.
    let prompt: String
    /// Whether the moment is active on the given date.
    let isActive: @Sendable (_ date: Date) -> Bool
}

/// The seasonal calendar: which moment, if any, is active for a region on a
/// given date.
enum SeasonalCalendar {
    /// The first active moment for `region` on `date`, or `nil` if none apply.
    static func activeMoment(region: Region, on date: Date) -> SeasonalMoment? {
        moments(for: region).first { $0.isActive(date) }
    }

    private static func moments(for region: Region) -> [SeasonalMoment] {
        switch region {
        case .denmark: denmark // TODO: Add more regions
        }
    }

    // MARK: - Denmark

    private static let denmark: [SeasonalMoment] = [
        SeasonalMoment(
            id: "summer_holiday",
            prompt: Prompt.Hints.Seasonal.Denmark.summerHoliday,
            // Danish school summer holiday: ISO weeks 27 through 31 inclusive.
            isActive: { inSeason($0, coreWeeks: 27 ... 31) }
        ),
        SeasonalMoment(
            id: "autumn_break",
            prompt: Prompt.Hints.Seasonal.Denmark.autumnBreak,
            // Efterårsferie: ISO week 42.
            isActive: { inSeason($0, coreWeeks: 42 ... 42) }
        ),
        SeasonalMoment(
            id: "halloween",
            prompt: Prompt.Hints.Seasonal.Denmark.halloween,
            // Halloween: the single day of October 31, plus the lead-up.
            isActive: { inSeason($0, onMonth: 10, day: 31) }
        ),
        SeasonalMoment(
            id: "christmas",
            prompt: Prompt.Hints.Seasonal.Denmark.christmas,
            // Christmas: anchored on juleaften (Dec 24), running through the
            // juledage (Dec 25–26). Lead-up reaches back to ~Dec 17.
            isActive: { inSeason($0, onMonth: 12, day: 24, trailingDays: 2) }
        ),
        SeasonalMoment(
            id: "new_years_eve",
            prompt: Prompt.Hints.Seasonal.Denmark.newYearsEve,
            // Nytårsaften: the single day of December 31.
            isActive: { inSeason($0, onMonth: 12, day: 31) }
        ),
        SeasonalMoment(
            id: "fastelavn",
            prompt: Prompt.Hints.Seasonal.Denmark.fastelavn,
            // Fastelavns søndag: 49 days (7 weeks) before Easter.
            isActive: { date in
                guard let easter = easter(for: date),
                      let fastelavn = gregorianCalendar.date(byAdding: .day, value: -49, to: easter)
                else { return false }
                return inSeason(date, on: fastelavn)
            }
        ),
        SeasonalMoment(
            id: "easter",
            prompt: Prompt.Hints.Seasonal.Denmark.easter,
            // Påske: anchored on Påskedag (Easter Sunday), running through 2.
            // påskedag. Lead-up reaches back to ~Palmesøndag (a week before).
            isActive: { date in
                guard let easter = easter(for: date) else { return false }
                return inSeason(date, on: easter, trailingDays: 1)
            }
        ),
    ]

    // MARK: - Window helpers

    /// How far ahead of a season we begin surfacing it, so the agent can raise
    /// it gently beforehand rather than only once it's underway. Expressed in
    /// whole weeks; ``leadDays`` mirrors it for day-anchored seasons.
    private static let leadWeeks = 1
    private static var leadDays: Int {
        leadWeeks * 7
    }

    /// `true` when `date` falls in a week-anchored season running over
    /// `coreWeeks`, extended ``leadWeeks`` earlier at the front for a short
    /// lead-up. The lead-up is baked in here so callers declare only the
    /// season's real weeks.
    ///
    /// Use this for stretches that run by the week (a holiday week, a school
    /// break). For events that fall on a single day, use ``inSeason(_:on:)``.
    private static func inSeason(_ date: Date, coreWeeks: ClosedRange<Int>) -> Bool {
        let window = (coreWeeks.lowerBound - leadWeeks) ... coreWeeks.upperBound
        return window.contains(isoWeek(of: date))
    }

    /// `true` when `date` falls in a day-anchored season: the lead-up of
    /// ``leadDays`` before the fixed `month`/`day` anchor, the anchor day
    /// itself, and `trailingDays` after it.
    ///
    /// Use this for events anchored on a date rather than a calendar week.
    /// Leave `trailingDays` at `0` for a single-day event (Halloween, New
    /// Year's Eve) so the hint clears once the day passes; raise it for a short
    /// stretch that hangs off one anchor (Christmas, anchored on the 24th but
    /// running through the days after). The anchor is resolved against `date`'s
    /// own (Gregorian) year.
    private static func inSeason(
        _ date: Date,
        onMonth month: Int,
        day: Int,
        trailingDays: Int = 0
    ) -> Bool {
        let year = gregorianCalendar.component(.year, from: date)
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let anchor = gregorianCalendar.date(from: components) else { return false }
        return inSeason(date, on: anchor, trailingDays: trailingDays)
    }

    /// `true` when `date` falls in a day-anchored season around a computed
    /// `anchor` date: the lead-up of ``leadDays`` before it, the anchor day
    /// itself, and `trailingDays` after it.
    ///
    /// Use this for moving holidays whose anchor isn't a fixed month/day
    /// (Easter and Fastelavn, derived from ``WesternEaster``).
    private static func inSeason(_ date: Date, on anchor: Date, trailingDays: Int = 0) -> Bool {
        guard let start = gregorianCalendar.date(byAdding: .day, value: -leadDays, to: anchor),
              let end = gregorianCalendar.date(byAdding: .day, value: 1 + trailingDays, to: anchor)
        else { return false }
        return date >= start && date < end
    }

    /// Western Easter Sunday for the year of `date`, if known.
    private static func easter(for date: Date) -> Date? {
        WesternEaster.date(year: gregorianCalendar.component(.year, from: date))
    }

    /// The ISO 8601 week-of-year for `date` in the device's timezone (weeks
    /// start Monday).
    private static func isoWeek(of date: Date) -> Int {
        isoCalendar.component(.weekOfYear, from: date)
    }

    /// ISO 8601 calendar (weeks start Monday) in the device's timezone, so week
    /// boundaries line up with the user's local sense of "this week".
    private static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    /// Gregorian calendar in the device's timezone, used for day-anchored
    /// windows where the ISO week-year would mislead near year boundaries.
    private static let gregorianCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()
}
