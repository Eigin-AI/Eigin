@testable import Eigin
import Foundation
import Testing

@Suite("BackgroundNotifyTool")
struct BackgroundNotifyToolTests {
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    @MainActor
    private func run(
        now: String, deliverAt: String? = nil, calendarIdentifier: Calendar.Identifier = .gregorian
    ) async throws -> (ToolResult, Date?) {
        let instant = date(now)
        var calendar = Calendar(identifier: calendarIdentifier)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        let signals = BackgroundSignalBox()
        let tool = BackgroundNotifyTool(
            now: { instant },
            calendar: calendar,
            isAuthorized: { true },
            onSignal: { signals.set($0) }
        )
        var arguments = [
            "notification_title": "Hello",
            "message": "Something useful",
            "summary": "Context",
        ]
        arguments["deliver_at"] = deliverAt
        let call = try ToolCall(
            id: "notify", type: "function",
            function: .init(
                name: "background_notify",
                arguments: String(decoding: JSONEncoder().encode(arguments), as: UTF8.self)
            )
        )
        let agent = Agent(name: "Eigin", providerID: UUID(), model: "test")
        let result = await tool.execute(call, agent: agent)
        var scheduled: Date?
        if case .notify(_, _, _, let deliverAt) = signals.value {
            scheduled = deliverAt
        }
        return (result, scheduled)
    }

    @Test("Omitted timing selects the next local slot", arguments: [
        ("2026-01-15T04:00:00Z", "2026-01-15T06:00:00Z"),
        ("2026-01-15T11:20:00Z", "2026-01-15T12:00:00Z"),
        ("2026-01-15T08:00:00Z", "2026-01-15T10:00:00Z"),
        ("2026-01-15T18:00:01Z", "2026-01-16T06:00:00Z"),
        ("2026-03-28T19:00:00Z", "2026-03-29T05:00:00Z"),
        ("2026-10-24T18:00:00Z", "2026-10-25T06:00:00Z"),
    ])
    @MainActor
    func defaultTiming(now: String, expected: String) async throws {
        let (result, scheduled) = try await run(now: now)
        #expect(!result.isError)
        #expect(scheduled == date(expected))
        let envelope = try #require(JSONSerialization
            .jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        let output = try #require(envelope["result"] as? [String: Any])
        let reportedTime = try #require(output["scheduled_for"] as? String)
        #expect(date(reportedTime) == scheduled)
    }

    @Test("Explicit future times override slots", arguments: [
        ("2026-01-16T02:30:00Z", "2026-01-16T02:30:00Z"),
        ("2026-01-15T12:30:00+01:00", "2026-01-15T11:30:00Z"),
        ("2026-01-15T12:30:00.500Z", "2026-01-15T12:30:00.500Z"),
        ("2026-01-15T12:30:00", "2026-01-15T11:30:00Z"),
    ])
    @MainActor
    func explicitTiming(input: String, expected: String) async throws {
        let (result, scheduled) = try await run(now: "2026-01-15T04:00:00Z", deliverAt: input)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedDate = formatter.date(from: expected) ?? date(expected)
        #expect(!result.isError)
        #expect(scheduled == expectedDate)
    }

    @Test("Timezone-less ISO dates use Gregorian years with the local timezone")
    @MainActor
    func nonGregorianCalendar() async throws {
        let (result, scheduled) = try await run(
            now: "2026-01-15T04:00:00Z",
            deliverAt: "2026-01-16T12:30:00",
            calendarIdentifier: .buddhist
        )
        #expect(!result.isError)
        #expect(scheduled == date("2026-01-16T11:30:00Z"))
    }

    @Test("Invalid or elapsed explicit times fail without notifying", arguments: [
        "2026-01-14T12:00:00Z", "2026-01-15T04:00:00Z", "tomorrow", "",
    ])
    @MainActor
    func invalidTiming(input: String) async throws {
        let (result, scheduled) = try await run(now: "2026-01-15T04:00:00Z", deliverAt: input)
        #expect(result.isError)
        #expect(scheduled == nil)
    }

    @Test("Missing authorization emits no background notification signal")
    @MainActor func deniedAuthorization() async {
        let tool = BackgroundNotifyTool(isAuthorized: { false }, onSignal: { _ in
            Issue.record("Unauthorized background notification must not emit a signal")
        })
        let call = ToolCall(
            id: "denied",
            type: "function",
            function: .init(
                name: "background_notify",
                arguments: #"{"notification_title":"Title","message":"Message","summary":"Briefing"}"#
            )
        )
        let result = await tool.execute(
            call,
            agent: Agent(name: "Test", providerID: UUID(), model: "test")
        )
        #expect(result.isError)
        #expect(result.content.contains("Settings"))
    }
}
