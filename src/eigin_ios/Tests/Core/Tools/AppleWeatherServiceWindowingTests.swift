@testable import Eigin
import Foundation
import Testing

@Suite("Apple Weather Service Windowing")
struct AppleWeatherServiceWindowingTests {
    // MARK: - Helpers

    /// A fixed UTC calendar so tests are timezone-stable.
    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    private static func hours(_ startTimes: [Date]) -> [HourWeather] {
        startTimes.map {
            HourWeather(
                hour: $0, condition: "Clear", temperatureCelsius: 20, precipitationChance: 0
            )
        }
    }

    private static func days(_ startTimes: [Date]) -> [DayWeather] {
        startTimes.map {
            DayWeather(
                date: $0, condition: "Clear", highCelsius: 22, lowCelsius: 12,
                precipitationChance: 0
            )
        }
    }

    // MARK: - restOfToday

    @Test func restOfTodayKeepsInProgressHourAndDropsElapsedAndNextDay() {
        let calendar = Self.utcCalendar()
        let now = Self.date(2026, 9, 14, 14, 37, calendar: calendar)
        let hours = Self.hours([
            Self.date(2026, 9, 14, 13, 0, calendar: calendar), // fully elapsed
            Self.date(2026, 9, 14, 14, 0, calendar: calendar), // in progress
            Self.date(2026, 9, 14, 15, 0, calendar: calendar),
            Self.date(2026, 9, 14, 23, 0, calendar: calendar), // last hour of today
            Self.date(2026, 9, 15, 0, 0, calendar: calendar), // tomorrow
        ])

        let result = AppleWeatherService.restOfToday(hours: hours, after: now, calendar: calendar)

        #expect(result.map(\.hour) == [
            Self.date(2026, 9, 14, 14, 0, calendar: calendar),
            Self.date(2026, 9, 14, 15, 0, calendar: calendar),
            Self.date(2026, 9, 14, 23, 0, calendar: calendar),
        ])
    }

    @Test func restOfTodayIncludesLastMinuteOfInProgressHour() {
        let calendar = Self.utcCalendar()
        // One minute before the in-progress hour ends.
        let now = Self.date(2026, 9, 14, 14, 59, calendar: calendar)
        let hours = Self.hours([Self.date(2026, 9, 14, 14, 0, calendar: calendar)])

        let result = AppleWeatherService.restOfToday(hours: hours, after: now, calendar: calendar)

        #expect(result.count == 1)
    }

    @Test func restOfTodayExcludesHourOnceItIsFullyElapsed() {
        let calendar = Self.utcCalendar()
        let now = Self.date(2026, 9, 14, 15, 0, calendar: calendar)
        let hours = Self.hours([Self.date(2026, 9, 14, 14, 0, calendar: calendar)])

        let result = AppleWeatherService.restOfToday(hours: hours, after: now, calendar: calendar)

        #expect(result.isEmpty)
    }

    // MARK: - Daily Forecast

    @Test func forecastDropsTodayAndLimitsCount() {
        let calendar = Self.utcCalendar()
        let now = Self.date(2026, 9, 14, 14, 37, calendar: calendar)
        let days = Self.days([
            Self.date(2026, 9, 14, 0, 0, calendar: calendar), // today — dropped
            Self.date(2026, 9, 15, 0, 0, calendar: calendar),
            Self.date(2026, 9, 16, 0, 0, calendar: calendar),
            Self.date(2026, 9, 17, 0, 0, calendar: calendar),
        ])

        let result = AppleWeatherService.forecast(
            days: days, after: now, count: 2, calendar: calendar
        )

        #expect(result.map(\.date) == [
            Self.date(2026, 9, 15, 0, 0, calendar: calendar),
            Self.date(2026, 9, 16, 0, 0, calendar: calendar),
        ])
    }

    @Test func forecastZeroCountReturnsEmpty() {
        let calendar = Self.utcCalendar()
        let now = Self.date(2026, 9, 14, 14, 37, calendar: calendar)
        let days = Self.days([
            Self.date(2026, 9, 14, 0, 0, calendar: calendar),
            Self.date(2026, 9, 15, 0, 0, calendar: calendar),
        ])

        let result = AppleWeatherService.forecast(
            days: days, after: now, count: 0, calendar: calendar
        )

        #expect(result.isEmpty)
    }
}
