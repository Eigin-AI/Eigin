@testable import Eigin
import Foundation
import SwiftData
import Testing
import UserNotifications

@Suite("Intent initiative agreements")
struct InitiativeServiceTests {
    @MainActor private func fixture(status: UNAuthorizationStatus = .authorized) throws -> Fixture {
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let center = FakeInitiativeNotifications()
        let scheduler = InitiativeNotificationScheduler(
            notifications: center,
            authorization: FakeNotificationAuthorization(status: status),
            contentPreparer: FakeCommunicationNotificationPreparer()
        )
        let agent = Agent(name: "Agent", providerID: UUID(), model: "test")
        container.mainContext.insert(agent)
        let intent = Intent(
            agentID: agent.id,
            content: "News",
            schedules: [IntentSchedule(content: "Morning", frequency: .daily, hour: 7, minute: 0)]
        )
        container.mainContext.insert(intent)
        try container.mainContext.save()
        return Fixture(
            container: container,
            center: center,
            service: InitiativeService(modelContainer: container, scheduler: scheduler),
            agent: agent,
            intent: intent
        )
    }

    @Test @MainActor func permissionDenialPersistsInAppAgreementAndTimeChange() async throws {
        let f = try fixture(status: .denied)
        var schedule = try #require(f.intent.schedules.first)
        schedule.hour = 9
        do {
            _ = try await f.service.apply(
                [f.change(schedule: schedule)],
                agentID: f.agent.id,
                spaceID: nil,
                canPromptUser: true
            )
            Issue.record("Expected denied permission")
        } catch {}
        let context = ModelContext(f.container)
        try seedTrackingBeforeLatestDue(context)
        #expect(try context.fetchCount(FetchDescriptor<IntentInitiative>()) == 1)
        #expect(try context.fetch(FetchDescriptor<Intent>()).first?.schedules.first?.hour == 9)
        #expect(f.center.requests.isEmpty)
        try WaitingInitiativeStore.reconcile(
            context: context,
            now: Date.now.addingTimeInterval(86400)
        )
        #expect(try context.fetchCount(FetchDescriptor<WaitingInitiative>()) == 1)
    }

    @Test @MainActor func agreementSurvivesRelaunchAndReschedulesWithoutBackground() async throws {
        let f = try fixture()
        _ = try await f.apply()
        #expect(f.center.requests.count == 1)
        let id = try #require(f.center.requests.first?.identifier)
        f.center.requests = []
        let freshService = InitiativeService(
            modelContainer: f.container,
            scheduler: f.service.scheduler
        )
        await freshService.reconcile()
        #expect(f.center.requests.map(\.identifier) == [id])
        #expect(try f.service.list(agentID: f.agent.id, spaceID: nil)
            .first?["status"] == "scheduled")
    }

    @Test @MainActor func resolveAndCancelRemoveNotifications() async throws {
        let f = try fixture()
        let results = try await f.apply()
        let idText = try #require(results.first?["id"])
        let id = try #require(UUID(uuidString: idText))
        try await f.service.cancel(id: id, agentID: f.agent.id, spaceID: nil)
        #expect(f.center.requests.isEmpty)
        _ = try await f.apply()
        let intents = DefaultIntentService(
            modelContainer: f.container,
            onChange: { await f.service.reconcile() }
        )
        try await intents.resolve(id: f.intent.id)
        #expect(f.center.requests.isEmpty)
    }

    @Test @MainActor func registrationFailureIsVisibleAndRetryable() async throws {
        let f = try fixture()
        f.center.dropAdds = true
        do { _ = try await f.apply(); Issue.record("Expected failed verification") } catch {}
        #expect(try f.service.list(agentID: f.agent.id, spaceID: nil)
            .first?["status"] != "scheduled")
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<IntentInitiative>()) == 1)
        f.center.dropAdds = false
        await f.service.reconcile()
        #expect(f.center.requests.count == 1)
    }

    @Test @MainActor func invalidChangedScheduleDoesNotCancelUnrelatedInitiatives() async throws {
        let f = try fixture()
        _ = try await f.apply()
        let context = ModelContext(f.container)
        try seedTrackingBeforeLatestDue(context)
        let other = Intent(
            agentID: f.agent.id,
            content: "Email",
            schedules: [IntentSchedule(content: "Email", frequency: .daily, hour: 12, minute: 0)]
        )
        context.insert(other)
        try context.save()
        _ = try await f.service.apply(
            [InitiativeChange(
                intentID: other.id,
                scheduleID: other.schedules[0].id,
                instructions: "Read current mail",
                body: "Time for email"
            )],
            agentID: f.agent.id,
            spaceID: nil,
            canPromptUser: true
        )
        let news = try #require(context.fetch(FetchDescriptor<Intent>())
            .first { $0.id == f.intent.id })
        news.schedules[0].frequency = .monthly
        news.schedules[0].monthDays = [31]
        try context.save()
        await f.service.reconcile()
        #expect(f.center.requests.count == 1)
        #expect(f.center.requests.first?.content.body == "Time for email")
    }

    @Test @MainActor func deletingAnOwningSpaceCancelsItsNotifications() async throws {
        let f = try fixture()
        let context = ModelContext(f.container)
        try seedTrackingBeforeLatestDue(context)
        let space = Space(agentID: f.agent.id)
        context.insert(space)
        let intent = try #require(context.fetch(FetchDescriptor<Intent>()).first)
        intent.spaceID = space.id
        try context.save()
        _ = try await f.service.apply(
            [f.change()],
            agentID: f.agent.id,
            spaceID: space.id,
            canPromptUser: true
        )
        #expect(f.center.requests.count == 1)
        context.delete(space)
        try context.save()
        await f.service.reconcile()
        #expect(f.center.requests.isEmpty)
    }

    @Test @MainActor func failedAdditionPreservesExistingAgreement() async throws {
        let f = try fixture()
        _ = try await f.apply()
        let original = try #require(f.center.requests.first?.identifier)
        let context = ModelContext(f.container)
        try seedTrackingBeforeLatestDue(context)
        let other = Intent(
            agentID: f.agent.id,
            content: "Email",
            schedules: [IntentSchedule(content: "Email", frequency: .daily, hour: 12, minute: 0)]
        )
        context.insert(other)
        try context.save()
        f.center.failAdds = true
        do {
            _ = try await f.service.apply(
                [InitiativeChange(
                    intentID: other.id,
                    scheduleID: other.schedules[0].id,
                    instructions: "Read current mail",
                    body: "Time for email"
                )],
                agentID: f.agent.id,
                spaceID: nil,
                canPromptUser: true
            )
            Issue.record("Expected failed addition")
        } catch {}
        #expect(f.center.requests.map(\.identifier) == [original])
    }

    @Test @MainActor func repeatedAndLateTapsCreateOneChatAndOneClaim() async throws {
        let f = try fixture()
        _ = try await f.apply()
        let id = try #require(f.center.requests.first?.identifier)
        let date = Date.now
        let context = ModelContext(f.container)
        try seedTrackingBeforeLatestDue(context)
        let first = try InitiativeConversationService.open(
            registrationID: id,
            deliveredAt: date,
            context: context
        )
        let repeated = try InitiativeConversationService.open(
            registrationID: id,
            deliveredAt: date,
            context: ModelContext(f.container)
        )
        #expect(first == repeated)
        #expect(try context.fetchCount(FetchDescriptor<Chat>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Message>()) == 0)
        #expect(try InitiativeConversationService.claimStart(chatID: first, context: context))
        #expect(try !InitiativeConversationService.claimStart(
            chatID: first,
            context: ModelContext(f.container)
        ))
        let next = try InitiativeConversationService.open(
            registrationID: id,
            deliveredAt: date.addingTimeInterval(86400),
            context: context,
            now: date.addingTimeInterval(86400)
        )
        #expect(next != first)
    }

    @Test @MainActor func cancellationBlocksStartupAndRetryOfOpenedOccurrence() async throws {
        let f = try fixture()
        let agreements = try await f.apply()
        let registration = try #require(f.center.requests.first?.identifier)
        let context = ModelContext(f.container)
        try seedTrackingBeforeLatestDue(context)
        let chatID = try InitiativeConversationService.open(
            registrationID: registration,
            deliveredAt: .now,
            context: context
        )
        let idText = try #require(agreements.first?["id"])
        let id = try #require(UUID(uuidString: idText))
        try await f.service.cancel(id: id, agentID: f.agent.id, spaceID: nil)
        let fresh = ModelContext(f.container)
        #expect(throws: (any Error).self) { try InitiativeConversationService.claimStart(
            chatID: chatID,
            context: fresh
        ) }
        #expect(throws: (any Error).self) { try InitiativeConversationService.validateTurn(
            chatID: chatID,
            messages: [],
            context: fresh
        ) }
    }

    @Test @MainActor func rejectedMonthlySetLeavesExistingAgreementIntact() async throws {
        let f = try fixture()
        _ = try await f.apply()
        let original = f.center.requests.map(\.identifier)
        var monthly = f.intent.schedules[0]
        monthly.frequency = .monthly
        do { _ = try await f.service.apply(
            [f.change(schedule: monthly)],
            agentID: f.agent.id,
            spaceID: nil,
            canPromptUser: true
        ); Issue.record("Expected monthly rejection") } catch {}
        #expect(f.center.requests.map(\.identifier) == original)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Intent>()).first?.schedules
            .first?.frequency == .daily)
    }

    @Test @MainActor func explicitRetryClaimsStartupAndCompletionPreventsAutomaticReplay(
    ) async throws {
        let f = try fixture()
        _ = try await f.apply()
        let registration = try #require(f.center.requests.first?.identifier)
        let context = ModelContext(f.container)
        try seedTrackingBeforeLatestDue(context)
        let chatID = try InitiativeConversationService.open(
            registrationID: registration,
            deliveredAt: .now,
            context: context
        )
        let messages: [ChatMessage] = []
        // A retry after provider setup reaches execution without the view's initial claim.
        #expect(try InitiativeConversationService.beginExecution(
            chatID: chatID,
            messages: messages,
            context: context
        ))
        #expect(!InitiativeConversationService.needsResume(chatID: chatID, context: context))
        #expect(throws: (any Error).self) { try InitiativeConversationService.beginExecution(
            chatID: chatID,
            messages: messages,
            context: context
        ) }
        try InitiativeConversationService.finishExecution(
            chatID: chatID,
            completed: true,
            context: context
        )
        let reopened = ModelContext(f.container)
        #expect(!InitiativeConversationService.hasPendingStart(chatID: chatID, context: reopened))
        #expect(!InitiativeConversationService.needsResume(chatID: chatID, context: reopened))
        #expect(try !InitiativeConversationService.claimStart(chatID: chatID, context: reopened))
    }

    @Test @MainActor func unfinishedClaimRequiresExplicitResume() async throws {
        let f = try fixture()
        _ = try await f.apply()
        let registration = try #require(f.center.requests.first?.identifier)
        let context = ModelContext(f.container)
        try seedTrackingBeforeLatestDue(context)
        let chatID = try InitiativeConversationService.open(
            registrationID: registration,
            deliveredAt: .now,
            context: context
        )
        #expect(try InitiativeConversationService.claimStart(chatID: chatID, context: context))
        let reopened = ModelContext(f.container)
        #expect(!InitiativeConversationService.hasPendingStart(chatID: chatID, context: reopened))
        #expect(InitiativeConversationService.needsResume(chatID: chatID, context: reopened))
        #expect(try InitiativeConversationService.beginExecution(
            chatID: chatID,
            messages: [],
            context: reopened
        ))
        try InitiativeConversationService.finishExecution(
            chatID: chatID,
            completed: false,
            context: reopened
        )
        #expect(InitiativeConversationService.needsResume(chatID: chatID, context: reopened))
    }

    @Test(arguments: ["intent", "agreement"])
    @MainActor func deletedInitiativeBlocksItsDeliveryAndPreservesOtherWork(
        deleted: String
    ) async throws {
        let f = try fixture()
        _ = try await f.apply()
        let context = ModelContext(f.container)
        try seedTrackingBeforeLatestDue(context)
        let other = Intent(
            agentID: f.agent.id,
            content: "Email",
            schedules: [IntentSchedule(content: "Email", frequency: .daily, hour: 7, minute: 0)]
        )
        context.insert(other)
        try context.save()
        _ = try await f.service.apply(
            [InitiativeChange(
                intentID: other.id,
                scheduleID: other.schedules[0].id,
                instructions: "Read email",
                body: "Email update"
            )],
            agentID: f.agent.id,
            spaceID: nil,
            canPromptUser: true
        )
        let registrationID = try #require(f.center.requests
            .first { $0.content.body == "Time for news" }?.identifier)
        #expect(try InitiativeConversationService.validatedDelivery(
            registrationID: registrationID,
            context: context
        ).members.count == 1)
        let chatID = try InitiativeConversationService.open(
            registrationID: registrationID,
            deliveredAt: .now,
            context: context
        )
        if deleted == "intent" {
            let intent = try #require(context.fetch(FetchDescriptor<Intent>())
                .first { $0.id == f.intent.id })
            context.delete(intent)
        } else {
            let agreement = try #require(context.fetch(FetchDescriptor<IntentInitiative>())
                .first { $0.intentID == f.intent.id })
            context.delete(agreement)
        }
        try context.save()
        #expect(throws: (any Error).self) { try InitiativeConversationService.claimStart(
            chatID: chatID,
            context: context
        ) }
        #expect(throws: (any Error).self) { try InitiativeConversationService.beginExecution(
            chatID: chatID,
            messages: [],
            context: context
        ) }
        await f.service.reconcile()
        #expect(f.center.requests.count == 1)
        let replacementID = try #require(f.center.requests.first?.identifier)
        #expect(replacementID != registrationID)
        let delivery = try InitiativeConversationService.validatedDelivery(
            registrationID: replacementID,
            context: ModelContext(f.container)
        )
        #expect(delivery.members.map(\.intentID) == [other.id])
    }

    @Test @MainActor func realUserMessageEndsAutomaticInitiativeStartup() async throws {
        let f = try fixture()
        let agreements = try await f.apply()
        let context = ModelContext(f.container)
        try seedTrackingBeforeLatestDue(context)
        let registration = try #require(f.center.requests.first?.identifier)
        let chatID = try InitiativeConversationService.open(
            registrationID: registration,
            deliveredAt: .now,
            context: context
        )
        let chat = try #require(context.fetch(FetchDescriptor<Chat>()).first { $0.id == chatID })
        let message = Message(role: "user", content: "Let's discuss something else")
        message.chat = chat
        context.insert(message)
        try context.save()
        let idText = try #require(agreements.first?["id"])
        let agreementID = try #require(UUID(uuidString: idText))
        try await f.service.cancel(id: agreementID, agentID: f.agent.id, spaceID: nil)
        #expect(!InitiativeConversationService.hasPendingStart(chatID: chatID, context: context))
        #expect(try !InitiativeConversationService.claimStart(chatID: chatID, context: context))
        #expect(try !InitiativeConversationService.beginExecution(
            chatID: chatID,
            messages: [message.toChatMessage()],
            context: context
        ))
        #expect(try context.fetch(FetchDescriptor<InitiativeOccurrence>()).first?.startedAt == nil)
    }

    @Test @MainActor func invalidExistingAgreementDoesNotBlockAValidSetter() async throws {
        let f = try fixture()
        _ = try await f.apply()
        let context = ModelContext(f.container)
        try seedTrackingBeforeLatestDue(context)
        let invalid = try #require(context.fetch(FetchDescriptor<Intent>()).first)
        invalid.schedules[0].frequency = .monthly
        invalid.schedules[0].monthDays = [31]
        let other = Intent(
            agentID: f.agent.id,
            content: "Email",
            schedules: [IntentSchedule(content: "Email", frequency: .daily, hour: 12, minute: 0)]
        )
        context.insert(other)
        try context.save()
        _ = try await f.service.apply(
            [InitiativeChange(
                intentID: other.id,
                scheduleID: other.schedules[0].id,
                instructions: "Read mail",
                body: "Time for email"
            )],
            agentID: f.agent.id,
            spaceID: nil,
            canPromptUser: true
        )
        #expect(f.center.requests.count == 1)
        #expect(f.center.requests.first?.content.body == "Time for email")
    }

    @Test @MainActor func nearbySuggestionsNeverShiftAgreedTimes() async throws {
        let f = try fixture()
        _ = try await f.apply()
        let context = ModelContext(f.container)
        try seedTrackingBeforeLatestDue(context)
        let other = Intent(
            agentID: f.agent.id,
            content: "Email",
            schedules: [IntentSchedule(content: "Email", frequency: .daily, hour: 7, minute: 30)]
        )
        context.insert(other)
        try context.save()
        _ = try await f.service.apply(
            [InitiativeChange(
                intentID: other.id,
                scheduleID: other.schedules[0].id,
                instructions: "Read mail",
                body: "Time for email"
            )],
            agentID: f.agent.id,
            spaceID: nil,
            canPromptUser: true
        )
        #expect(try f.service.nearbySuggestions(agentID: f.agent.id, spaceID: nil).count == 1)
        #expect(f.center.requests.count == 2)
        let times = try f.service.list(agentID: f.agent.id, spaceID: nil).compactMap { $0["time"] }
        #expect(Set(times) == ["07:00", "07:30"])
    }

    @Test @MainActor func suppliedDaySelectionsAreAppliedWithoutRepeatingFrequency() async throws {
        let f = try fixture()
        let tool = SetInitiativesTool(service: f.service, spaceID: nil, canPromptUser: true)
        func call(_ selection: String) -> ToolCall {
            ToolCall(id: "set", type: "function", function: .init(name: tool.name, arguments: """
            {"changes":[{"intent_id":"\(f.intent.id)","schedule_id":"\(f.intent
                .schedules[0]
                .id)","instructions":"Get current news","notification":"Time for news",\(
                selection
            )}]}
            """))
        }
        let weekdays = await tool.execute(call("\"daily_pattern\":\"weekdays\""), agent: f.agent)
        #expect(!weekdays.isError)
        #expect(f.center.requests.count == 5)
        let selected = await tool.execute(call("\"weekdays\":[1,7]"), agent: f.agent)
        #expect(!selected.isError)
        #expect(f.center.requests.count == 2)
        let invalid = await tool.execute(
            call("\"frequency\":\"daily\",\"weekdays\":[2]"),
            agent: f.agent
        )
        #expect(invalid.isError)
        #expect(f.center.requests.count == 2)
    }

    @Test @MainActor func capacityAllocatesWholeInitiativesAndKeepsInAppDiscovery() async throws {
        let f = try fixture()
        f.center.requests = (0 ..< 59).map {
            UNNotificationRequest(
                identifier: "other-\($0)",
                content: UNMutableNotificationContent(),
                trigger: nil
            )
        }
        var schedule = f.intent.schedules[0]
        schedule.frequency = .weekly
        schedule.weekdays = [2, 3, 4, 5, 6]
        do {
            _ = try await f.service.apply(
                [f.change(schedule: schedule)],
                agentID: f.agent.id,
                spaceID: nil,
                canPromptUser: true
            )
            Issue.record("Expected a saved agreement with unavailable system delivery")
        } catch let failure as InitiativeOperationFailure {
            #expect(failure.changesState == .saved)
        }
        #expect(f.center.requests.count == 59)
        let report = try await f.service.report(agentID: f.agent.id, spaceID: nil)
        #expect(report.first?["in_app"] as? String == "enabled")
        #expect(report.first?["registered_request_count"] as? Int == 0)
        let context = ModelContext(f.container)
        try WaitingInitiativeStore.reconcile(
            context: context,
            now: Date.now.addingTimeInterval(7 * 86400)
        )
        #expect(try context.fetchCount(FetchDescriptor<WaitingInitiative>()) == 1)
    }

    @MainActor private func seedTrackingBeforeLatestDue(_ context: ModelContext) throws {
        for cursor in try context.fetch(FetchDescriptor<InitiativeCursor>()) {
            cursor.evaluatedThrough = Date.now.addingTimeInterval(-86400)
        }
        try context.save()
    }

    @MainActor private struct Fixture {
        let container: ModelContainer
        let center: FakeInitiativeNotifications
        let service: InitiativeService
        let agent: Agent
        let intent: Intent
        func change(schedule: IntentSchedule? = nil) -> InitiativeChange {
            InitiativeChange(
                intentID: intent.id,
                scheduleID: intent.schedules[0].id,
                instructions: "Fetch current news",
                body: "Time for news",
                schedule: schedule
            )
        }

        func apply() async throws -> [[String: String]] {
            try await service.apply(
                [change()],
                agentID: agent.id,
                spaceID: nil,
                canPromptUser: true
            )
        }
    }
}
