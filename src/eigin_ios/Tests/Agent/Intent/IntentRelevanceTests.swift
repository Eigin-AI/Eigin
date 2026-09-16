@testable import Eigin
import Foundation
import Testing

@Suite("Intent relevance and temporal logic")
struct IntentRelevanceTests {
    // MARK: - Helpers

    /// Fixed calendar so occurrence math is deterministic across machines.
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        return c
    }()

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    private func snapshot(
        content: String = "Goal",
        tasks: [IntentTask] = [],
        events: [IntentEvent] = [],
        schedules: [IntentSchedule] = [],
        updatedAt: Date = .now
    ) -> IntentSnapshot {
        IntentSnapshot(
            id: UUID(),
            content: content,
            status: .active,
            tasks: tasks,
            events: events,
            schedules: schedules,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Schedule occurrences

    @Test func dailyScheduleFindsNextSlot() {
        let schedule = IntentSchedule(content: "log sleep", frequency: .daily, hour: 9)
        // Before today's slot → today at 09:00.
        #expect(
            schedule.nextOccurrence(onOrAfter: date(2026, 6, 10, 8), calendar: calendar)
                == date(2026, 6, 10, 9)
        )
        // After today's slot → tomorrow at 09:00.
        #expect(
            schedule.nextOccurrence(onOrAfter: date(2026, 6, 10, 10), calendar: calendar)
                == date(2026, 6, 11, 9)
        )
    }

    @Test func weeklyScheduleLandsOnRequestedWeekday() {
        let target = date(2026, 6, 12, 9)
        let weekday = calendar.component(.weekday, from: target)
        let schedule = IntentSchedule(
            content: "gardening", frequency: .weekly, weekdays: [weekday], hour: 9
        )
        #expect(
            schedule.nextOccurrence(onOrAfter: date(2026, 6, 10, 8), calendar: calendar) == target
        )
    }

    @Test func monthlyScheduleLandsOnRequestedDay() {
        let schedule = IntentSchedule(
            content: "pay rent", frequency: .monthly, monthDays: [15], hour: 9
        )
        #expect(
            schedule.nextOccurrence(onOrAfter: date(2026, 6, 10), calendar: calendar)
                == date(2026, 6, 15, 9)
        )
    }

    @Test func malformedScheduleHasNoOccurrence() {
        // Weekly with no weekdays can't fire.
        let schedule = IntentSchedule(content: "x", frequency: .weekly)
        #expect(schedule.nextOccurrence(onOrAfter: date(2026, 6, 10), calendar: calendar) == nil)
    }

    // MARK: - Relevance blending

    @Test func dueScheduleOutranksStalePlainIntent() {
        let now = date(2026, 6, 10, 9)
        let scheduled = snapshot(
            schedules: [IntentSchedule(content: "log sleep", frequency: .daily, hour: 9)],
            updatedAt: date(2026, 6, 1)
        )
        let stale = snapshot(updatedAt: date(2026, 6, 1))

        #expect(
            IntentRelevance.relevance(for: scheduled, at: now)
                > IntentRelevance.relevance(for: stale, at: now)
        )
    }

    @Test func nearerEventOutranksFartherEvent() {
        let now = date(2026, 6, 10)
        let soon = snapshot(events: [IntentEvent(content: "gift", at: date(2026, 6, 12))])
        let later = snapshot(events: [IntentEvent(content: "gift", at: date(2026, 6, 16))])

        #expect(
            IntentRelevance.relevance(for: soon, at: now)
                > IntentRelevance.relevance(for: later, at: now)
        )
    }

    // MARK: - Asymmetric bell shape

    @Test func scheduleDecaysFastAfterFiring() {
        let schedule = IntentSchedule(content: "log sleep", frequency: .daily, hour: 9)
        // Equal 6h distance either side of the 09:00 slot.
        let before = snapshot(schedules: [schedule], updatedAt: date(2026, 6, 10))
        let after = snapshot(schedules: [schedule], updatedAt: date(2026, 6, 10))

        #expect(
            IntentRelevance.relevance(for: before, at: date(2026, 6, 11, 3))
                > IntentRelevance.relevance(for: after, at: date(2026, 6, 10, 15))
        )
        // Total relevance 6h after the slot is under half of the same 6h
        // distance before it — the trail decays much faster than the lead.
        // (The symmetric falloff it replaces scores the same on both sides.)
        #expect(
            IntentRelevance.relevance(for: after, at: date(2026, 6, 10, 15))
                < 0.5 * IntentRelevance.relevance(for: before, at: date(2026, 6, 11, 3))
        )
    }

    @Test func eventHasTailAfterPassing() {
        let now = date(2026, 6, 10)
        let recent = snapshot(
            events: [IntentEvent(content: "birthday", at: date(2026, 6, 9))],
            updatedAt: now
        )
        let old = snapshot(
            events: [IntentEvent(content: "birthday", at: date(2026, 6, 6))],
            updatedAt: now
        )

        // Past events keep real pull for a while, then fade.
        #expect(IntentRelevance.relevance(for: recent, at: now) > 0.5)
        #expect(
            IntentRelevance.relevance(for: recent, at: now)
                > IntentRelevance.relevance(for: old, at: now)
        )
    }

    @Test func bellIsAsymmetricApproachOutlastsRecede() {
        // Same distance either side of the peak: the approaching side scores higher.
        #expect(
            IntentRelevance.timeBell(
                offset: 3600, lead: IntentRelevance.scheduleLead,
                trail: IntentRelevance.scheduleTrail
            )
                > IntentRelevance.timeBell(
                    offset: -3600, lead: IntentRelevance.scheduleLead,
                    trail: IntentRelevance.scheduleTrail
                )
        )
        #expect(
            IntentRelevance.timeBell(
                offset: 86400, lead: IntentRelevance.eventLead, trail: IntentRelevance.eventTrail
            )
                > IntentRelevance.timeBell(
                    offset: -86400, lead: IntentRelevance.eventLead,
                    trail: IntentRelevance.eventTrail
                )
        )
    }

    @Test func eventPeakIsMaximum() {
        let event = IntentEvent(content: "flight", at: date(2026, 6, 10, 12))
        let intent = snapshot(events: [event], updatedAt: date(2026, 6, 10, 12))

        #expect(
            IntentRelevance.relevance(for: intent, at: date(2026, 6, 10, 12))
                >= IntentRelevance.relevance(for: intent, at: date(2026, 6, 10, 11))
        )
        #expect(
            IntentRelevance.relevance(for: intent, at: date(2026, 6, 10, 12))
                >= IntentRelevance.relevance(for: intent, at: date(2026, 6, 10, 13))
        )
    }

    @Test func openTasksOutrankCompletedAllElseEqual() {
        let now = date(2026, 6, 10)
        let updatedAt = date(2026, 6, 9)
        let open = snapshot(tasks: [IntentTask(content: "do thing")], updatedAt: updatedAt)
        let done = snapshot(
            tasks: [IntentTask(content: "do thing", completed: true)], updatedAt: updatedAt
        )

        #expect(
            IntentRelevance.relevance(for: open, at: now)
                > IntentRelevance.relevance(for: done, at: now)
        )
    }

    @Test func recencyBreaksTiesBetweenPlainIntents() {
        let now = date(2026, 6, 10)
        let fresh = snapshot(updatedAt: date(2026, 6, 9))
        let older = snapshot(updatedAt: date(2026, 5, 20))

        #expect(
            IntentRelevance.relevance(for: fresh, at: now)
                > IntentRelevance.relevance(for: older, at: now)
        )
    }

    @Test func recencyStillContributesUnderEqualSchedules() {
        let now = date(2026, 6, 10, 9)
        let schedule = IntentSchedule(content: "log sleep", frequency: .daily, hour: 9)
        let fresh = snapshot(schedules: [schedule], updatedAt: date(2026, 6, 9))
        let older = snapshot(schedules: [schedule], updatedAt: date(2026, 5, 1))

        // Same dominant schedule signal, so recency must still separate them.
        #expect(
            IntentRelevance.relevance(for: fresh, at: now)
                > IntentRelevance.relevance(for: older, at: now)
        )
    }

    // MARK: - Digest cues

    @Test func digestSummarisesTimelyState() throws {
        // IntentDigest reads Calendar.current internally, so build the fixture
        // in that same calendar to keep the "today" boundary deterministic.
        let cal = Calendar.current
        let midnight = try cal.startOfDay(for: #require(cal.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 10
        ))))
        let now = try #require(cal.date(byAdding: .hour, value: 8, to: midnight))
        let eventAt = cal.date(byAdding: .hour, value: 3 * 24 + 12, to: midnight)!

        let intent = snapshot(
            tasks: [
                IntentTask(content: "a"),
                IntentTask(content: "b", completed: true),
            ],
            events: [IntentEvent(content: "birthday", at: eventAt)],
            schedules: [IntentSchedule(content: "log sleep", frequency: .daily, hour: 9)]
        )
        let cues = IntentDigest.cues(for: intent, at: now)
        #expect(cues.contains("scheduled today"))
        #expect(cues.contains("in 3 days"))
        #expect(cues.contains("1 open task"))
    }

    @Test func digestIsEmptyWhenNothingTimely() {
        let intent = snapshot()
        #expect(IntentDigest.summary(for: intent, at: .now) == nil)
    }
}
