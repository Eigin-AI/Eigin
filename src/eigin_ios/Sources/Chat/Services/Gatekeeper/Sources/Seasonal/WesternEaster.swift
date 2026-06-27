import Foundation

/// Western (Gregorian) Easter Sunday. Easter moves each year and other seasonal
/// moments hang off it (like Danish Fastelavn 49 days earlier), so it lives
/// here as a region-agnostic primitive.
///
/// Backed by a lookup table rather than the computus algorithm.
/// Extend the table before it runs out.
enum WesternEaster {
    /// Easter Sunday for `year`, or `nil` if the year is outside the table.
    static func date(year: Int) -> Date? {
        guard let monthDay = table[year] else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = monthDay.month
        components.day = monthDay.day
        return calendar.date(from: components)
    }

    /// Easter Sunday as (month, day) by year.
    private static let table: [Int: (month: Int, day: Int)] = [
        2025: (4, 20),
        2026: (4, 5),
        2027: (3, 28),
        2028: (4, 16),
        2029: (4, 1),
        2030: (4, 21),
        2031: (4, 13),
        2032: (3, 28),
        2033: (4, 17),
        2034: (4, 9),
        2035: (3, 25),
        2036: (4, 13),
    ]

    /// Gregorian calendar in the device's timezone, matching the day-anchored
    /// window math in ``SeasonalCalendar`` so the dates compare cleanly.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()
}
