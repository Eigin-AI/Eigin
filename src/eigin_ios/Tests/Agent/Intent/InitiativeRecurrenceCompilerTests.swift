@testable import Eigin
import Foundation
import Testing
import UserNotifications

@Suite("Recurring initiative notifications")
struct InitiativeRecurrenceCompilerTests {
    private let agentID = UUID()

    @Test func dailyTasksShareOneIndefinitePattern() throws {
        let news = initiative()
        let email = initiative()
        let patterns = try compile([news, email])
        let pattern = try #require(patterns.first)
        #expect(patterns.count == 1)
        #expect(pattern.weekday == nil)
        #expect(Set(pattern.initiativeIDs) == [news.initiativeID, email.initiativeID])
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: pattern.dateComponents,
            repeats: true
        )
        #expect(trigger.repeats)
        #expect(trigger.dateComponents.second == 0)
        #expect(trigger.dateComponents.timeZone == nil)
        #expect(trigger.dateComponents.calendar == nil)
        #expect(trigger.nextTriggerDate() != nil)
    }

    @Test func dailyAndMondayTasksNeverCreateOverlappingAlerts() throws {
        let daily = initiative()
        let monday = initiative(weekdays: [2])
        let patterns = try compile([daily, monday])
        #expect(patterns.count == 7)
        for day in 1 ... 7 {
            let matches = patterns.filter { $0.weekday == nil || $0.weekday == day }
            #expect(matches.count == 1)
            let expected: Set<UUID> = day == 2
                ? [daily.initiativeID, monday.initiativeID] : [daily.initiativeID]
            #expect(try Set(#require(matches.first).initiativeIDs) == expected)
        }
    }

    @Test func dailyPresetsKeepWeekdaysAndWeekendsSeparate() throws {
        let work = initiative(weekdays: InitiativeDailyPattern.weekdays.weekdays)
        let rest = initiative(weekdays: InitiativeDailyPattern.weekends.weekdays)
        let patterns = try compile([work, rest])
        #expect(patterns.count == 7)
        for day in 1 ... 7 {
            let match = try #require(patterns.first { $0.weekday == day })
            #expect(match
                .initiativeIDs == [day == 1 || day == 7 ? rest.initiativeID : work.initiativeID])
        }
        let everyDay = initiative(weekdays: InitiativeDailyPattern.everyDay.weekdays)
        #expect(try compile([everyDay]).first?.weekday == nil)
    }

    @Test func allWeeklySubsetsHaveExactMembership() throws {
        let daily = initiative()
        for mask in 1 ..< 128 {
            let weekdays = (1 ... 7).filter { mask & (1 << ($0 - 1)) != 0 }
            let weekly = initiative(weekdays: weekdays)
            let patterns = try compile([weekly, daily])
            for day in 1 ... 7 {
                let matches = patterns.filter { $0.weekday == nil || $0.weekday == day }
                #expect(matches.count == 1)
                let expected: Set<UUID> = weekdays.contains(day)
                    ? [daily.initiativeID, weekly.initiativeID] : [daily.initiativeID]
                #expect(try Set(#require(matches.first).initiativeIDs) == expected)
            }
        }
    }

    @Test func differentAgentsSpacesAndTimesStaySeparate() throws {
        let global = initiative()
        let privateSpace = initiative(spaceID: UUID())
        let anotherAgent = initiative(agent: UUID())
        let later = initiative(minute: 30)
        let patterns = try compile([global, privateSpace, anotherAgent, later])
        #expect(patterns.count == 4)
        #expect(patterns.allSatisfy { $0.initiativeIDs.count == 1 })
        #expect(patterns.contains { $0.minute == 30 })
    }

    @Test func capacityFailureDoesNotReturnAPartialSchedule() throws {
        let inputs = [initiative(), initiative(weekdays: [2])]
        #expect(throws: InitiativeScheduleError.capacityExceeded(required: 7, available: 6)) {
            try InitiativeRecurrenceCompiler.compile(inputs, availableRequestCount: 6)
        }
        #expect(try InitiativeRecurrenceCompiler.compile(inputs, availableRequestCount: 7)
            .count == 7)
        #expect(try InitiativeRecurrenceCompiler.compile([], availableRequestCount: 0).isEmpty)
    }

    @Test func monthlyNotificationsAreExplicitlyUnsupported() {
        let monthly = initiative(frequency: .monthly)
        #expect(throws: InitiativeScheduleError.unsupportedMonthlySchedule) {
            try compile([monthly])
        }
    }

    @Test func invalidSchedulesAreRejected() {
        for weekdays in [[], [0], [8], [2, 9]] {
            #expect(throws: InitiativeScheduleError.invalidWeekdays) {
                try compile([initiative(weekdays: weekdays)])
            }
        }
        #expect(throws: InitiativeScheduleError.explicitTimeRequired) {
            try compile([initiative(hour: nil)])
        }
        #expect(throws: InitiativeScheduleError.explicitTimeRequired) {
            try compile([initiative(minute: nil)])
        }
        for hour in [-1, 24] {
            #expect(throws: InitiativeScheduleError.invalidTime) {
                try compile([initiative(hour: hour)])
            }
        }
        #expect(throws: InitiativeScheduleError.invalidTime) {
            try compile([initiative(minute: 60)])
        }
        #expect(throws: InitiativeScheduleError.invalidRequestBudget) {
            try InitiativeRecurrenceCompiler.compile([], availableRequestCount: -1)
        }
    }

    @Test func registrationPlanIsIndependentOfInputOrder() throws {
        let inputs = [initiative(), initiative(weekdays: [2, 2, 4]), initiative(spaceID: UUID())]
        #expect(try compile(inputs) == compile(inputs.reversed()))
        #expect(throws: InitiativeScheduleError.duplicateInitiative) {
            try compile([inputs[0], inputs[0]])
        }
    }

    @Test func weeklySystemTriggersMatchTheirRequestedWeekday() throws {
        let patterns = try compile([initiative(), initiative(weekdays: [2])])
        let calendar = Calendar(identifier: .gregorian)
        for pattern in patterns {
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: pattern.dateComponents,
                repeats: true
            )
            let next = try #require(trigger.nextTriggerDate())
            #expect(calendar.component(.weekday, from: next) == pattern.weekday)
            #expect(calendar.component(.hour, from: next) == pattern.hour)
            #expect(calendar.component(.minute, from: next) == pattern.minute)
            #expect(calendar.component(.second, from: next) == 0)
        }
    }

    private func compile(_ inputs: [InitiativeSchedule]) throws -> [InitiativeNotificationPattern] {
        try InitiativeRecurrenceCompiler.compile(inputs, availableRequestCount: 60)
    }

    private func initiative(
        agent: UUID? = nil,
        spaceID: UUID? = nil,
        frequency: ScheduleFrequency? = nil,
        weekdays: [Int]? = nil,
        hour: Int? = 7,
        minute: Int? = 0
    ) -> InitiativeSchedule {
        InitiativeSchedule(
            initiativeID: UUID(), intentID: UUID(), agentID: agent ?? agentID, spaceID: spaceID,
            schedule: IntentSchedule(
                content: "Gather current news",
                frequency: frequency ?? (weekdays == nil ? .daily : .weekly),
                weekdays: weekdays, hour: hour, minute: minute
            )
        )
    }
}
