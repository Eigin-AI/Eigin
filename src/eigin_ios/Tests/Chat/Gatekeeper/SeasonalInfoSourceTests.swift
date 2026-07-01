@testable import Eigin
import Foundation
import Testing

@Suite("Seasonal")
@MainActor
struct SeasonalInfoSourceTests {
    // MARK: - Helpers

    /// A date at midday on the given day, in the current timezone — midday so a
    /// timezone offset can't nudge it across an ISO week boundary.
    private func midday(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.timeZone = .current
        return Calendar.current.date(from: components)!
    }

    private func denmarkResolver() -> RegionResolver {
        RegionResolver(regionCode: { "DK" }, timeZoneIdentifier: { "Europe/Copenhagen" })
    }

    private func unknownResolver() -> RegionResolver {
        RegionResolver(regionCode: { "US" }, timeZoneIdentifier: { "America/New_York" })
    }

    private func input(isSmallContext: Bool = false) -> SystemHintInput {
        SystemHintInput(
            agentID: UUID(),
            bootstrapComplete: true,
            needsCompaction: false,
            hasSpaces: false,
            messages: [],
            space: nil,
            spaceID: nil,
            language: nil,
            mode: .text,
            activeIntents: [],
            activeSkills: [],
            availableSkills: [],
            activeFlow: nil,
            provider: ProviderSnapshot(name: "Test Provider", baseURL: "https://test.example.com"),
            modelID: "test-model",
            isSmallContext: isSmallContext
        )
    }

    // MARK: - SeasonalCalendar

    @Test("summer holiday is active inside ISO weeks 27–31")
    func summerHolidayActive() {
        // 2026-07-15 falls in ISO week 29.
        let moment = SeasonalCalendar.activeMoment(
            region: .denmark,
            on: midday(year: 2026, month: 7, day: 15)
        )
        #expect(moment?.id == "summer_holiday")
    }

    @Test("a season surfaces a week ahead of its first week")
    func leadUpBeforeFirstWeek() {
        // 2026-06-24 falls in ISO week 26 — the lead-up week before summer's
        // first core week (27).
        let moment = SeasonalCalendar.activeMoment(
            region: .denmark,
            on: midday(year: 2026, month: 6, day: 24)
        )
        #expect(moment?.id == "summer_holiday")
    }

    @Test("autumn break is active in ISO week 42")
    func autumnBreakActive() {
        // 2026-10-15 falls in ISO week 42.
        let moment = SeasonalCalendar.activeMoment(
            region: .denmark,
            on: midday(year: 2026, month: 10, day: 15)
        )
        #expect(moment?.id == "autumn_break")
    }

    @Test("halloween is day-anchored: lead-up through Oct 31, then clears")
    func halloweenWindow() {
        func id(_ month: Int, _ day: Int) -> String? {
            SeasonalCalendar.activeMoment(
                region: .denmark,
                on: midday(year: 2026, month: month, day: day)
            )?.id
        }
        #expect(id(10, 24) == "halloween") // a week ahead — lead-up
        #expect(id(10, 31) == "halloween") // the day itself
        #expect(id(11, 1) == nil) // cleared the day after, not left to linger
        #expect(id(10, 23) == nil) // before the lead-up begins
    }

    @Test("christmas spans juleaften through the juledage, with a lead-up")
    func christmasWindow() {
        func id(_ month: Int, _ day: Int) -> String? {
            SeasonalCalendar.activeMoment(
                region: .denmark,
                on: midday(year: 2026, month: month, day: day)
            )?.id
        }
        #expect(id(12, 17) == "christmas") // ~a week ahead — lead-up
        #expect(id(12, 24) == "christmas") // juleaften
        #expect(id(12, 26) == "christmas") // 2. juledag — still in season
        #expect(id(12, 16) == nil) // before the lead-up begins
        #expect(id(12, 27) != "christmas") // cleared after the juledage (new year's eve takes over)
    }

    @Test("new year's eve takes over after christmas through Dec 31")
    func newYearsEveWindow() {
        func id(_ year: Int, _ month: Int, _ day: Int) -> String? {
            SeasonalCalendar.activeMoment(
                region: .denmark,
                on: midday(year: year, month: month, day: day)
            )?.id
        }
        #expect(id(2026, 12, 26) == "christmas") // christmas still owns the juledage
        #expect(id(2026, 12, 27) == "new_years_eve") // hands off once christmas clears
        #expect(id(2026, 12, 31) == "new_years_eve") // nytårsaften
        #expect(id(2027, 1, 1) == nil) // cleared in the new year
    }

    @Test("fastelavn is anchored 49 days before Easter, plus a lead-up")
    func fastelavnWindow() {
        /// Easter 2026 is Apr 5, so Fastelavn is Feb 15; lead-up reaches Feb 8.
        func id(_ month: Int, _ day: Int) -> String? {
            SeasonalCalendar.activeMoment(
                region: .denmark,
                on: midday(year: 2026, month: month, day: day)
            )?.id
        }
        #expect(id(2, 8) == "fastelavn") // a week ahead — lead-up
        #expect(id(2, 15) == "fastelavn") // fastelavns søndag
        #expect(id(2, 16) == nil) // cleared the day after
        #expect(id(2, 7) == nil) // before the lead-up begins
    }

    @Test("easter spans Palmesøndag through 2. påskedag")
    func easterWindow() {
        /// Easter Sunday 2026 is Apr 5; window runs Mar 29 (E−7) through Apr 6.
        func id(_ month: Int, _ day: Int) -> String? {
            SeasonalCalendar.activeMoment(
                region: .denmark,
                on: midday(year: 2026, month: month, day: day)
            )?.id
        }
        #expect(id(3, 29) == "easter") // ~Palmesøndag — lead-up
        #expect(id(4, 5) == "easter") // påskedag
        #expect(id(4, 6) == "easter") // 2. påskedag — trailing
        #expect(id(4, 7) == nil) // cleared after the holiday
        #expect(id(3, 28) == nil) // before the lead-up begins
    }

    @Test("Easter-derived moments stay silent for years outside the table")
    func easterUnknownYear() {
        // 1900 is not in the WesternEaster table, so nothing derived can fire.
        #expect(WesternEaster.date(year: 1900) == nil)
        #expect(SeasonalCalendar.activeMoment(
            region: .denmark,
            on: midday(year: 1900, month: 4, day: 15)
        ) == nil)
    }

    @Test("no moment is active outside the wired windows")
    func outsideWindowInactive() {
        // March and late November fall outside the summer and autumn windows;
        // the remaining moments are stubs that never fire.
        #expect(SeasonalCalendar.activeMoment(
            region: .denmark,
            on: midday(year: 2026, month: 3, day: 15)
        ) == nil)
        #expect(SeasonalCalendar.activeMoment(
            region: .denmark,
            on: midday(year: 2026, month: 11, day: 25)
        ) == nil)
    }

    // MARK: - SeasonalInfoSource

    @Test("renders the seasonal hint for a Danish user in summer")
    func rendersForDenmarkInSummer() async {
        let date = midday(year: 2026, month: 7, day: 15)
        let source = SeasonalInfoSource(now: { date }, regionResolver: denmarkResolver())
        #expect(await source.render(input()) != nil)
    }

    @Test("silent outside the seasonal window")
    func silentOutsideWindow() async {
        let date = midday(year: 2026, month: 3, day: 15)
        let source = SeasonalInfoSource(now: { date }, regionResolver: denmarkResolver())
        #expect(await source.render(input()) == nil)
    }

    @Test("silent when the region is unknown")
    func silentWhenRegionUnknown() async {
        let date = midday(year: 2026, month: 7, day: 15)
        let source = SeasonalInfoSource(now: { date }, regionResolver: unknownResolver())
        #expect(await source.render(input()) == nil)
    }

    @Test("silent in compact mode")
    func silentInCompact() async {
        let date = midday(year: 2026, month: 7, day: 15)
        let source = SeasonalInfoSource(now: { date }, regionResolver: denmarkResolver())
        #expect(await source.render(input(isSmallContext: true)) == nil)
    }
}
