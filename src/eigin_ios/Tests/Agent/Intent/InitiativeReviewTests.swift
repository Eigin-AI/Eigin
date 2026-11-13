@testable import Eigin
import Foundation
import SwiftData
import Testing
import UserNotifications

@Suite("Initiative review regressions")
@MainActor
struct InitiativeReviewTests {
    @Test func updateIntentSavesReschedulingWithoutPermissionAndAllowsRemoval() async throws {
        let f = try fixture()
        _ = try await f.enable()
        let denied = InitiativeService(
            modelContainer: f.container,
            scheduler: InitiativeNotificationScheduler(
                notifications: f.center,
                authorization: FakeNotificationAuthorization(status: .denied),
                contentPreparer: FakeCommunicationNotificationPreparer()
            )
        )
        let service = DefaultIntentService(modelContainer: f.container, initiatives: { denied })
        let tool = UpdateIntentTool(intentService: service)
        let changed = await tool.execute(updateCall(f, schedules: """
        [{"id":"\(f.schedule.id)","content":"News","frequency":"daily","hour":9,"minute":0}]
        """), agent: f.agent)
        #expect(changed.isError)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Intent>()).first?.schedules
            .first?.hour == 9)
        let removed = await tool.execute(updateCall(f, schedules: "[]"), agent: f.agent)
        #expect(!removed.isError)
        #expect(f.center.requests.isEmpty)
    }

    @Test func updateIntentSavesDespiteCapacityAndReportsRegistrationFailure() async throws {
        let f = try fixture()
        _ = try await f.enable()
        let second = Intent(
            agentID: f.agent.id,
            content: "Email",
            schedules: [IntentSchedule(content: "Email", frequency: .daily, hour: 7, minute: 0)]
        )
        f.container.mainContext.insert(second)
        try f.container.mainContext.save()
        _ = try await f.service.apply(
            [InitiativeChange(
                intentID: second.id,
                scheduleID: second.schedules[0].id,
                instructions: "Read mail",
                body: "Time for mail"
            )],
            agentID: f.agent.id,
            spaceID: nil,
            canPromptUser: true
        )
        f.center.requests += (0 ..< 59).map { UNNotificationRequest(
            identifier: "other-\($0)",
            content: UNMutableNotificationContent(),
            trigger: nil
        ) }
        let service = DefaultIntentService(modelContainer: f.container, initiatives: { f.service })
        let tool = UpdateIntentTool(intentService: service)
        let result = await tool.execute(updateCall(f, schedules: """
        [{"id":"\(f.schedule
            .id)","content":"News","frequency":"weekly","weekdays":["monday"],"hour":7,"minute":0}]
        """), agent: f.agent)
        #expect(result.isError)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Intent>())
            .first(where: { $0.id == f.intent.id })?.schedules.first?.frequency == .weekly)
        f.center.requests.removeAll { $0.identifier.hasPrefix("other-") }
        f.center.failAdds = true
        let failed = await tool.execute(updateCall(f, schedules: """
        [{"id":"\(f.schedule.id)","content":"News","frequency":"daily","hour":9,"minute":0}]
        """), agent: f.agent)
        #expect(failed.isError)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Intent>())
            .first(where: { $0.id == f.intent.id })?.schedules.first?.hour == 9)
    }

    @Test func schedulingToolReturnsStablePermissionAndRecurrenceFailureCodes() async throws {
        let f = try fixture()
        let denied = InitiativeService(
            modelContainer: f.container,
            scheduler: InitiativeNotificationScheduler(
                notifications: f.center,
                authorization: FakeNotificationAuthorization(status: .denied),
                contentPreparer: FakeCommunicationNotificationPreparer()
            )
        )
        let deniedTool = SetInitiativesTool(
            service: denied,
            spaceID: nil,
            canPromptUser: true
        )
        let deniedResult = await deniedTool.execute(setCall(f), agent: f.agent)
        let deniedJSON = try result(deniedResult)
        #expect(deniedResult.isError)
        #expect(deniedJSON["status"] as? String == "permission_required")
        #expect(deniedJSON["changes_state"] as? String == "saved")
        #expect((deniedJSON["initiatives"] as? [[String: Any]])?
            .first?["in_app"] as? String == "enabled")
        let tool = SetInitiativesTool(service: f.service, spaceID: nil, canPromptUser: true)
        let unsupported = await tool.execute(
            setCall(f, extra: ",\"frequency\":\"monthly\""),
            agent: f.agent
        )
        #expect(try result(unsupported)["status"] as? String == "unsupported_recurrence")
        #expect(try result(unsupported)["changes_state"] as? String == "not_saved")
    }

    @Test func partialBatchFailureReportsWhichSavedAgreementsAreInstalled() async throws {
        let f = try fixture()
        let second = Intent(
            agentID: f.agent.id,
            content: "Email",
            schedules: [IntentSchedule(content: "Email", frequency: .daily, hour: 12, minute: 0)]
        )
        f.container.mainContext.insert(second)
        try f.container.mainContext.save()
        f.center.failAfter = 1
        let call = ToolCall(
            id: "set",
            type: "function",
            function: .init(name: "set_initiatives", arguments: """
            {"changes":[
              {"intent_id":"\(f.intent.id)","schedule_id":"\(f.schedule
                .id)","instructions":"Read news","notification":"News time"},
              {"intent_id":"\(second.id)","schedule_id":"\(second.schedules[0]
                .id)","instructions":"Read mail","notification":"Mail time"}
            ]}
            """)
        )
        let response = await SetInitiativesTool(
            service: f.service,
            spaceID: nil,
            canPromptUser: true
        ).execute(call, agent: f.agent)
        let json = try result(response)
        #expect(response.isError)
        #expect(json["status"] as? String == "registration_failed")
        #expect(json["changes_state"] as? String == "saved")
        let agreements = try #require(json["initiatives"] as? [[String: Any]])
        #expect(agreements.count == 2)
        #expect(agreements.allSatisfy { $0["saved"] as? Bool == true })
        #expect(Set(agreements.compactMap { $0["delivery_status"] as? String }) == [
            "scheduled",
            "not_registered",
        ])
        #expect(agreements.compactMap { $0["registered_request_count"] as? Int }.sorted() == [0, 1])
    }

    @Test func intentDetailsDistinguishPendingScheduledFailedAndDisabledAgreements() async throws {
        let f = try fixture()
        f.center.dropAdds = true
        do { _ = try await f.enable(); Issue.record("Expected failed registration") } catch {}
        func status() throws -> InitiativeStatus {
            let context = ModelContext(f.container)
            let agreement = try #require(context.fetch(FetchDescriptor<IntentInitiative>()).first)
            let intent = try #require(context.fetch(FetchDescriptor<Intent>()).first)
            return InitiativeStatus(initiative: agreement, intent: intent)
        }
        #expect(try status().state == .failed)
        #expect(try status().nextOccurrence != nil)
        f.center.dropAdds = false
        await f.service.reconcile()
        #expect(try status().state == .scheduled)
        #expect(try status().nextOccurrence != nil)
        let context = ModelContext(f.container)
        let agreement = try #require(context.fetch(FetchDescriptor<IntentInitiative>()).first)
        agreement.registrationStatus = "pending"
        try context.save()
        #expect(try status().state == .pending)
        #expect(try status().nextOccurrence != nil)
        try await f.service.cancel(id: agreement.id, agentID: f.agent.id, spaceID: nil)
        #expect(try status().state == .disabled)
        #expect(try !status().canCancel)
    }

    @Test func permissionRevokedAfterSaveReportsSavedChanges() async throws {
        let f = try fixture(authorization: SequencedNotificationAuthorization([
            .authorized,
            .denied,
        ]))
        let tool = SetInitiativesTool(service: f.service, spaceID: nil, canPromptUser: true)
        let response = await tool.execute(setCall(f), agent: f.agent)
        let json = try result(response)
        #expect(response.isError)
        #expect(json["status"] as? String == "permission_required")
        #expect(json["changes_state"] as? String == "saved")
        let agreements = try #require(json["initiatives"] as? [[String: Any]])
        #expect(agreements.count == 1)
        #expect(agreements.first?["saved"] as? Bool == true)
        #expect(agreements.first?["delivery_status"] as? String == "not_registered")
    }

    @Test func capacityChangedAfterSaveReportsSavedChanges() async throws {
        let f = try fixture()
        let competing = (0 ..< 60).map { UNNotificationRequest(
            identifier: "other-\($0)",
            content: UNMutableNotificationContent(),
            trigger: nil
        ) }
        f.center.pendingSnapshots = [competing, competing]
        let tool = SetInitiativesTool(service: f.service, spaceID: nil, canPromptUser: true)
        let response = await tool.execute(setCall(f), agent: f.agent)
        let json = try result(response)
        #expect(response.isError)
        #expect(json["status"] as? String == "registration_failed")
        #expect(json["changes_state"] as? String == "saved")
        let agreements = try #require(json["initiatives"] as? [[String: Any]])
        #expect(agreements.first?["saved"] as? Bool == true)
        #expect(agreements.first?["registered_request_count"] as? Int == 0)
    }

    @Test(arguments: ["intent_id", "schedule_id"])
    func malformedIDsIdentifyTheFieldWithoutSaving(field: String) async throws {
        let f = try fixture()
        let tool = SetInitiativesTool(service: f.service, spaceID: nil, canPromptUser: true)
        for invalid: Any in ["test-news-1100", "", 123, NSNull()] {
            var change: [String: Any] = [
                "intent_id": f.intent.id.uuidString, "schedule_id": f.schedule.id.uuidString,
                "instructions": "AI news brief from TLDR and HN",
                "notification": "Time for your news",
                "daily_pattern": "every_day", "hour": 10, "minute": 57,
            ]
            change[field] = invalid
            let response = try await tool.execute(
                call("set_initiatives", ["changes": [change]]),
                agent: f.agent
            )
            let json = try result(response)
            #expect(response.isError)
            #expect(json["status"] as? String == "invalid_\(field)")
            #expect(json["changes_state"] as? String == "not_saved")
            #expect(response.content.contains("list_intents"))
            #expect(try f.container.mainContext
                .fetchCount(FetchDescriptor<IntentInitiative>()) == 0)
            #expect(f.center.requests.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func assignedScheduleIDsEnableInitiativesWithoutAnotherLookup(updating: Bool) async throws {
        let f = try fixture()
        let service = DefaultIntentService(modelContainer: f.container, initiatives: { f.service })
        var schedules: [[String: Any]] = []
        if updating {
            schedules.append([
                "id": f.schedule.id.uuidString,
                "content": f.schedule.content,
                "frequency": "daily",
                "hour": 7,
                "minute": 0,
            ])
        }
        schedules.append([
            "id": "test-news-1100",
            "content": "AI news brief",
            "frequency": "daily",
            "hour": 10,
            "minute": 57,
        ])
        let response: ToolResult = if updating {
            try await UpdateIntentTool(intentService: service).execute(
                call("update_intent", ["id": f.intent.id.uuidString, "schedules": schedules]),
                agent: f.agent
            )
        } else {
            try await AddIntentTool(intentService: service).execute(
                call("add_intent", ["content": "AI news", "schedules": schedules]),
                agent: f.agent
            )
        }
        #expect(!response.isError)
        let created = try result(response)
        let intentID = try #require(created["id"] as? String)
        let returned = try #require(created["schedules"] as? [[String: Any]])
        let scheduleID = try #require(returned.last?["id"] as? String)
        #expect(UUID(uuidString: scheduleID) != nil)
        #expect(returned.last?["content"] as? String == "AI news brief")
        if updating { #expect(returned.first?["id"] as? String == f.schedule.id.uuidString) }
        let persisted = try #require(ModelContext(f.container).fetch(FetchDescriptor<Intent>())
            .first { $0.id.uuidString == intentID })
        #expect(persisted.schedules.map { $0.id.uuidString } == returned
            .compactMap { $0["id"] as? String })
        let enabled = try await SetInitiativesTool(
            service: f.service,
            spaceID: nil,
            canPromptUser: true
        ).execute(call("set_initiatives", ["changes": [[
            "intent_id": intentID, "schedule_id": scheduleID,
            "instructions": "AI news brief from TLDR and HN", "notification": "Time for your news",
            "daily_pattern": "every_day", "hour": 10, "minute": 57,
        ]]]), agent: f.agent)
        #expect(!enabled.isError)
        #expect(f.center.requests.count == 1)
    }

    private func call(_ name: String, _ arguments: [String: Any]) throws -> ToolCall {
        try ToolCall(
            id: "test",
            type: "function",
            function: .init(
                name: name,
                arguments: String(
                    decoding: JSONSerialization.data(withJSONObject: arguments),
                    as: UTF8.self
                )
            )
        )
    }

    private func result(_ response: ToolResult) throws -> [String: Any] {
        let envelope = try #require(ToolHelpers.parseArguments(response.content))
        return try #require(envelope["result"] as? [String: Any])
    }

    private func updateCall(_ f: Fixture, schedules: String) -> ToolCall {
        ToolCall(
            id: "update",
            type: "function",
            function: .init(
                name: "update_intent",
                arguments: "{\"id\":\"\(f.intent.id)\",\"schedules\":\(schedules)}"
            )
        )
    }

    private func setCall(_ f: Fixture, extra: String = "") -> ToolCall {
        ToolCall(
            id: "set",
            type: "function",
            function: .init(name: "set_initiatives", arguments: """
            {"changes":[{"intent_id":"\(f.intent.id)","schedule_id":"\(f.schedule
                .id)","instructions":"Get news","notification":"Time for news"\(extra)}]}
            """)
        )
    }

    private func fixture(authorization: (any NotificationAuthorizationAccess)? = nil) throws
        -> Fixture
    {
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Test", providerID: UUID(), model: "test")
        let schedule = IntentSchedule(content: "News", frequency: .daily, hour: 7, minute: 0)
        let intent = Intent(agentID: agent.id, content: "News", schedules: [schedule])
        container.mainContext.insert(agent)
        container.mainContext.insert(intent)
        try container.mainContext.save()
        let center = FakeInitiativeNotifications()
        let service = InitiativeService(
            modelContainer: container,
            scheduler: InitiativeNotificationScheduler(
                notifications: center,
                authorization: authorization ?? FakeNotificationAuthorization(status: .authorized),
                contentPreparer: FakeCommunicationNotificationPreparer()
            )
        )
        return Fixture(
            container: container,
            agent: agent,
            intent: intent,
            schedule: schedule,
            center: center,
            service: service
        )
    }

    @MainActor private struct Fixture {
        let container: ModelContainer
        let agent: Agent
        let intent: Intent
        let schedule: IntentSchedule
        let center: FakeInitiativeNotifications
        let service: InitiativeService
        func enable() async throws -> [[String: String]] {
            try await service.apply(
                [InitiativeChange(
                    intentID: intent.id,
                    scheduleID: schedule.id,
                    instructions: "Get news",
                    body: "Time for news"
                )],
                agentID: agent.id,
                spaceID: nil,
                canPromptUser: true
            )
        }
    }
}
