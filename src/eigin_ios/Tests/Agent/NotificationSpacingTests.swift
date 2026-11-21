@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Notification spacing")
struct NotificationSpacingTests {
    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private func policy(_ zone: String = "UTC") -> NotificationSpacingPolicy {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return NotificationSpacingPolicy(calendar: calendar)
    }

    private func once(_ date: Date, id: UUID = UUID()) -> NotificationSpacingSchedule {
        NotificationSpacingSchedule(id: id, timing: .once(date))
    }

    private func recurring(
        hour: Int,
        minute: Int,
        days: [Int]? = nil
    ) -> NotificationSpacingSchedule {
        NotificationSpacingSchedule(id: UUID(), timing: .recurring(IntentSchedule(
            content: "Test", frequency: days == nil ? .daily : .weekly,
            weekdays: days, hour: hour, minute: minute
        )))
    }

    @Test("Durable recurring agreements block one-offs across agents and spaces")
    @MainActor func durableInventory() throws {
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Other", providerID: UUID(), model: "test")
        let schedule = IntentSchedule(content: "Morning", frequency: .daily, hour: 9, minute: 0)
        let space = Space(agentID: agent.id)
        container.mainContext.insert(space)
        let intent = Intent(
            agentID: agent.id,
            content: "Other",
            spaceID: space.id,
            schedules: [schedule]
        )
        let agreement = IntentInitiative(
            intentID: intent.id,
            scheduleID: schedule.id,
            instructions: "Work",
            notificationBody: "Invitation"
        )
        container.mainContext.insert(agent)
        container.mainContext.insert(intent)
        container.mainContext.insert(agreement)
        try container.mainContext.save()
        let validator = NotificationSpacingValidator(container: container, policy: policy())
        #expect(throws: NotificationSpacingConflict.self) {
            try validator.validate(
                date: date("2026-01-15T09:00:00Z"),
                now: date("2026-01-01T00:00:00Z")
            )
        }
        #expect(try validator.validate(
            date: date("2026-01-15T09:10:00Z"),
            now: date("2026-01-01T00:00:00Z")
        ).count == 1)
        agreement.enabled = false
        try container.mainContext.save()
        #expect(try validator.validate(
            date: date("2026-01-15T09:00:00Z"),
            now: date("2026-01-01T00:00:00Z")
        ).isEmpty)
    }

    @Test("Active registration snapshots reserve their original timezone")
    @MainActor func registrationInventory() throws {
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let schedule = IntentSchedule(content: "Morning", frequency: .daily, hour: 9, minute: 0)
        let agent = Agent(name: "Other", providerID: UUID(), model: "test")
        container.mainContext.insert(agent)
        let intent = Intent(agentID: agent.id, content: "Other", schedules: [schedule])
        let agreement = IntentInitiative(
            intentID: intent.id,
            scheduleID: schedule.id,
            instructions: "Work",
            notificationBody: "Invitation"
        )
        let delivery = InitiativeDelivery(
            identityVersion: 2,
            timeZoneIdentifier: "America/New_York",
            agentID: intent.agentID,
            spaceID: nil,
            hour: 9,
            minute: 0,
            weekday: nil,
            members: [.init(
                initiativeID: agreement.id,
                intentID: intent.id,
                schedule: schedule,
                instructions: "Work",
                body: "Invitation",
                revision: .now
            )]
        )
        let registration = try InitiativeRegistration(id: "old-zone", payload: delivery.encoded())
        container.mainContext.insert(intent)
        container.mainContext.insert(agreement)
        container.mainContext.insert(registration)
        try container.mainContext.save()
        let validator = NotificationSpacingValidator(
            container: container,
            policy: policy("Europe/Copenhagen")
        )
        #expect(throws: NotificationSpacingConflict.self) {
            try validator.validate(
                date: date("2026-01-15T14:00:00Z"),
                now: date("2026-01-01T00:00:00Z")
            )
        }
        registration.retiredAt = .now
        try container.mainContext.save()
        #expect(try validator.validate(
            date: date("2026-01-15T14:00:00Z"),
            now: date("2026-01-01T00:00:00Z")
        ).isEmpty)
    }

    @Test(
        "Exactly five minutes is allowed with a warning in both directions",
        arguments: [-901, -900, -301, -300, -299, 0, 299, 300, 301, 900, 901]
    )
    func boundaries(seconds: Int) throws {
        let now = date("2026-01-01T00:00:00Z")
        let existing = now.addingTimeInterval(3600)
        let proposed = existing.addingTimeInterval(Double(seconds))
        if abs(seconds) < 300 {
            #expect(throws: NotificationSpacingConflict.self) {
                try policy().validate(
                    proposed: [once(proposed)],
                    existing: [once(existing)],
                    now: now
                )
            }
        } else {
            let warnings = try policy().validate(
                proposed: [once(proposed)],
                existing: [once(existing)],
                now: now
            )
            #expect(warnings.count == (abs(seconds) <= 900 ? 1 : 0))
        }
    }

    @Test("Batch members conflict and replacement identities exclude their old time")
    func batchesAndReplacement() throws {
        let now = date("2026-01-01T00:00:00Z")
        let first = once(now.addingTimeInterval(3600))
        #expect(throws: NotificationSpacingConflict.self) {
            try policy().validate(
                proposed: [first, once(now.addingTimeInterval(3601))],
                existing: [],
                now: now
            )
        }
        #expect(try policy().validate(proposed: [first], existing: [first], now: now).isEmpty)
    }

    @Test("One-offs compare actual recurrence dates in both directions")
    func oneOffAndRecurring() throws {
        let now = date("2026-01-01T00:00:00Z")
        let a = once(date("2026-06-08T09:00:00Z"))
        let b = recurring(hour: 9, minute: 0, days: [2])
        let boundary = once(date("2026-06-08T09:05:00Z"))
        for pair in [(boundary, b), (b, boundary)] {
            #expect(try policy().validate(proposed: [pair.0], existing: [pair.1], now: now)
                .count == 1)
        }
        #expect(try policy().validate(
            proposed: [recurring(hour: 9, minute: 5, days: [2])],
            existing: [b],
            now: now
        ).count == 1)
        for pair in [(a, b), (b, a)] {
            #expect(throws: NotificationSpacingConflict.self) {
                try policy().validate(proposed: [pair.0], existing: [pair.1], now: now)
            }
        }
        #expect(try policy().validate(
            proposed: [once(date("2026-06-09T09:00:00Z"))],
            existing: [b],
            now: now
        ).isEmpty)
    }

    @Test("Recurring spacing crosses midnight and the week boundary")
    func weekBoundary() throws {
        let now = date("2026-01-01T00:00:00Z")
        #expect(throws: NotificationSpacingConflict.self) {
            try policy().validate(
                proposed: [recurring(hour: 0, minute: 1, days: [1])],
                existing: [recurring(hour: 23, minute: 59, days: [7])],
                now: now
            )
        }
        #expect(try policy().validate(
            proposed: [recurring(hour: 9, minute: 0, days: [2])],
            existing: [recurring(hour: 9, minute: 0, days: [3])],
            now: now
        ).isEmpty)
    }

    @Test("Spring-forward collision is detected months before the transition")
    func futureDST() {
        #expect(throws: NotificationSpacingConflict.self) {
            try policy("America/New_York").validate(
                proposed: [recurring(hour: 1, minute: 59, days: [1])],
                existing: [recurring(hour: 3, minute: 1, days: [1])],
                now: date("2026-01-01T00:00:00Z")
            )
        }
    }

    @Test("A repeating notification uses the first repeated hour")
    func repeatedHour() throws {
        let now = date("2026-10-01T00:00:00Z")
        let warnings = try policy("America/New_York").validate(
            proposed: [once(date("2026-11-01T06:34:00Z"))],
            existing: [recurring(hour: 1, minute: 30)], now: now
        )
        #expect(warnings.isEmpty)
    }

    @Test("Installed recurrence can retain a different timezone")
    func installedZone() throws {
        let schedule = IntentSchedule(content: "Test", frequency: .daily, hour: 9, minute: 0)
        #expect(throws: NotificationSpacingConflict.self) {
            try policy("Europe/Copenhagen").validate(
                proposed: [once(date("2026-01-15T14:00:00Z"))],
                existing: [NotificationSpacingSchedule(
                    id: UUID(),
                    timing: .recurring(
                        schedule,
                        timeZone: #require(TimeZone(identifier: "America/New_York"))
                    )
                )],
                now: date("2026-01-01T00:00:00Z")
            )
        }
    }
}
