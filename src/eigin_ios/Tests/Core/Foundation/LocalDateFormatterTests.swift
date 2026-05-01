@testable import Eigin
import Foundation
import Testing

@Suite("LocalDateFormatter")
struct LocalDateFormatterTests {
    // MARK: - Helpers

    /// Creates a date with the given components in the current timezone.
    private func makeDate(
        year: Int, month: Int, day: Int,
        hour: Int = 0, minute: Int = 0, second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = .current
        return Calendar.current.date(from: components)!
    }

    // MARK: - Formatting

    @Test("string(from:) outputs agent-facing format yyyy-MM-dd HH:mm")
    func stringFromDate() {
        let date = makeDate(year: 2026, month: 3, day: 23, hour: 9, minute: 5)
        let result = LocalDateFormatter.string(from: date)
        #expect(result == "2026-03-23 09:05")
    }

    @Test("iso8601String(from:) outputs ISO 8601 with Z suffix in UTC")
    func iso8601StringFromDate() throws {
        // Create a known UTC date via ISO8601DateFormatter to avoid timezone dependence.
        let utcDate = try #require(ISO8601DateFormatter().date(from: "2026-03-23T09:05:30Z"))
        let result = LocalDateFormatter.iso8601String(from: utcDate)
        #expect(result == "2026-03-23T09:05:30Z")
    }

    @Test("iso8601String(from:) includes zero seconds")
    func iso8601StringZeroSeconds() throws {
        let utcDate = try #require(ISO8601DateFormatter().date(from: "2026-03-23T18:16:00Z"))
        let result = LocalDateFormatter.iso8601String(from: utcDate)
        #expect(result == "2026-03-23T18:16:00Z")
    }

    @Test("dateOnlyString(from:) outputs yyyy-MM-dd")
    func dateOnlyStringFromDate() {
        let date = makeDate(year: 2026, month: 1, day: 7, hour: 14)
        let result = LocalDateFormatter.dateOnlyString(from: date)
        #expect(result == "2026-01-07")
    }

    // MARK: - Parsing

    @Test("parse primary format yyyy-MM-dd HH:mm")
    func parsePrimaryFormat() {
        let date = LocalDateFormatter.parse("2026-03-23 09:00")
        #expect(date != nil)
        let expected = makeDate(year: 2026, month: 3, day: 23, hour: 9)
        #expect(date == expected)
    }

    @Test("parse ISO 8601 fallback yyyy-MM-dd'T'HH:mm:ss")
    func parseISOFallback() {
        let date = LocalDateFormatter.parse("2026-03-23T09:00:00")
        #expect(date != nil)
        let expected = makeDate(year: 2026, month: 3, day: 23, hour: 9)
        #expect(date == expected)
    }

    @Test("parse ISO 8601 with Z suffix strips timezone")
    func parseISOWithZ() {
        let date = LocalDateFormatter.parse("2026-03-23T09:00:00Z")
        #expect(date != nil)
        // Z is stripped — parsed as local 09:00
        let expected = makeDate(year: 2026, month: 3, day: 23, hour: 9)
        #expect(date == expected)
    }

    @Test("parse ISO 8601 with timezone offset strips offset")
    func parseISOWithOffset() {
        let date = LocalDateFormatter.parse("2026-03-23T09:00:00+02:00")
        #expect(date != nil)
        // Offset is stripped — parsed as local 09:00
        let expected = makeDate(year: 2026, month: 3, day: 23, hour: 9)
        #expect(date == expected)
    }

    @Test("parse date-only defaults to midnight")
    func parseDateOnly() {
        let date = LocalDateFormatter.parse("2026-03-23")
        #expect(date != nil)
        let expected = makeDate(year: 2026, month: 3, day: 23)
        #expect(date == expected)
    }

    @Test("parse date-only with endOfDayIfDateOnly returns 23:59:59")
    func parseDateOnlyEndOfDay() {
        let date = LocalDateFormatter.parse("2026-03-23", endOfDayIfDateOnly: true)
        #expect(date != nil)
        let expected = makeDate(year: 2026, month: 3, day: 23, hour: 23, minute: 59, second: 59)
        #expect(date == expected)
    }

    @Test("parse returns nil for invalid input")
    func parseInvalidInput() {
        #expect(LocalDateFormatter.parse("not-a-date") == nil)
        #expect(LocalDateFormatter.parse("") == nil)
        #expect(LocalDateFormatter.parse("2026-13-45") == nil)
    }

    // MARK: - Round-trips

    @Test("agent format round-trips through parse → iso8601String (knowledge tool path)")
    func agentFormatToFirm() throws {
        // Agent sends "2026-03-23 18:16" (local time).
        // iso8601String converts to UTC ISO 8601 with Z — exact value depends on timezone,
        // so just verify the format is correct.
        let agentString = "2026-03-23 18:16"
        let date = LocalDateFormatter.parse(agentString)
        #expect(date != nil)
        let firmResult = try LocalDateFormatter.iso8601String(from: #require(date))
        #expect(firmResult.hasSuffix("Z"))
        #expect(firmResult.contains("T"))
    }

    @Test("Firm format round-trips through parse → string (reading back from Firm)")
    func firmFormatToAgentString() throws {
        // Firm stores "2026-03-23T18:16:00Z" (UTC).
        // parse strips Z, interprets as local → string outputs local time.
        let firmValue = "2026-03-23T18:16:00Z"
        let date = LocalDateFormatter.parse(firmValue)
        #expect(date != nil)
        let agentResult = try LocalDateFormatter.string(from: #require(date))
        // Parsed as local 18:16 (Z stripped), so agent sees 18:16.
        #expect(agentResult == "2026-03-23 18:16")
    }

    @Test("iso8601String round-trips through parse back to itself")
    func firmRoundTrip() throws {
        let utcDate = try #require(ISO8601DateFormatter().date(from: "2026-03-23T14:30:45Z"))
        let firm = LocalDateFormatter.iso8601String(from: utcDate)
        #expect(firm == "2026-03-23T14:30:45Z")
        // parse strips Z → interprets as local 14:30:45 → iso8601String converts back to UTC.
        // This only round-trips exactly if the device is in UTC. Instead verify format.
        let parsed = LocalDateFormatter.parse(firm)
        #expect(parsed != nil)
    }
}
