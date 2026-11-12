@testable import Eigin
import Foundation
import SwiftData
import Testing
import UserNotifications

@Suite("Waiting prepared follow-ups")
@MainActor struct WaitingFollowUpTests {
    private let baseline = Date(timeIntervalSince1970: 1_767_225_600)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func fixture() throws -> (ModelContainer, Agent, Space) {
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Agent", providerID: UUID(), model: "test")
        let space = Space(agentID: agent.id)
        container.mainContext.insert(agent)
        container.mainContext.insert(space)
        try container.mainContext.save()
        return (container, agent, space)
    }

    @discardableResult private func add(
        _ container: ModelContainer,
        agent: Agent,
        due: Date?,
        spaceID: UUID? = nil,
        message: String = "Prepared message"
    ) throws -> UUID {
        let request = AgentInitiativeRequest(
            agentID: agent.id,
            message: message,
            title: "Check in",
            summary: "Earlier context"
        )
        request.dueAt = due
        request.spaceID = spaceID
        container.mainContext.insert(request)
        try container.mainContext.save()
        return request.id
    }

    @Test func dueBoundaryLegacyExclusionAndNextRefresh() throws {
        let (container, agent, _) = try fixture()
        try add(container, agent: agent, due: nil)
        let due = baseline.addingTimeInterval(60)
        let id = try add(container, agent: agent, due: due)
        let context = ModelContext(container)
        #expect(try WaitingInitiativeStore.reconcile(context: context, now: baseline) == due)
        #expect(try WaitingMessageStore.messages(context: context, now: due.addingTimeInterval(-1))
            .isEmpty)
        try WaitingInitiativeStore.reconcile(context: context, now: due)
        #expect(try WaitingMessageStore.messages(context: context, now: due)
            .map(\.id) == ["follow-up:\(id.uuidString)"])
        try WaitingMessageStore.dismissFollowUp(id: id, context: context, now: due)
        try WaitingInitiativeStore.reconcile(
            context: ModelContext(container),
            now: due.addingTimeInterval(86400)
        )
        #expect(try WaitingMessageStore.messages(
            context: ModelContext(container),
            now: due.addingTimeInterval(86400)
        ).isEmpty)
    }

    @Test func mixedRetentionDisplacesBothKindsAndNeverRefills() throws {
        let (container, agent, space) = try fixture()
        for hour in [1, 3, 5, 7] {
            let schedule = IntentSchedule(
                content: "Daily",
                frequency: .daily,
                hour: hour,
                minute: 0
            )
            let intent = Intent(agentID: agent.id, content: "Routine", schedules: [schedule])
            container.mainContext.insert(intent)
            container.mainContext.insert(IntentInitiative(
                intentID: intent.id,
                scheduleID: schedule.id,
                instructions: "Help",
                notificationBody: "Recurring \(hour)"
            ))
        }
        for hour in [2, 4, 6, 10] {
            try add(
                container,
                agent: agent,
                due: baseline.addingTimeInterval(Double(hour) * 3600),
                spaceID: space.id,
                message: "Prepared \(hour)"
            )
        }
        let context = ModelContext(container)
        try WaitingInitiativeStore.reconcile(context: context, now: baseline, calendar: calendar)
        let six = baseline.addingTimeInterval(6 * 3600)
        try WaitingInitiativeStore.reconcile(context: context, now: six, calendar: calendar)
        #expect(try WaitingMessageStore.messages(context: context, now: six).map(\.body) == [
            "Prepared 6",
            "Recurring 5",
            "Prepared 4",
            "Recurring 3",
            "Prepared 2",
        ])
        let seven = baseline.addingTimeInterval(7 * 3600)
        try WaitingInitiativeStore.reconcile(context: context, now: seven, calendar: calendar)
        let items = try WaitingMessageStore.messages(context: context, now: seven)
        #expect(items.map(\.body) == [
            "Recurring 7",
            "Prepared 6",
            "Recurring 5",
            "Prepared 4",
            "Recurring 3",
        ])
        for item in items {
            switch item.source {
            case .recurring(let id): try WaitingInitiativeStore.dismiss(id: id, context: context)
            case .followUp(let id): _ = try WaitingMessageStore.openFollowUp(
                    id: id,
                    context: context,
                    now: seven
                )
            }
        }
        let fresh = ModelContext(container)
        try WaitingInitiativeStore.reconcile(
            context: fresh,
            now: seven.addingTimeInterval(1),
            calendar: calendar
        )
        #expect(try WaitingMessageStore.messages(context: fresh, now: seven.addingTimeInterval(1))
            .isEmpty)
        let discarded = try #require(fresh.fetch(FetchDescriptor<AgentInitiativeRequest>())
            .first(where: { $0.message == "Prepared 2" }))
        #expect(discarded.disposition == "discarded")
        #expect(throws: (any Error).self) { try WaitingMessageStore.openFollowUp(
            id: discarded.id,
            context: fresh,
            now: seven
        ) }
    }

    @Test(arguments: [
        true,
        false,
    ]) func cardAndNotificationShareOnePreparedChat(cardFirst: Bool) throws {
        let (container, agent, space) = try fixture()
        let message = "**Prepared**\n\n" + String(
            repeating: "Full message with details. ",
            count: 30
        )
        let id = try add(
            container,
            agent: agent,
            due: Date.now.addingTimeInterval(-60),
            spaceID: space.id,
            message: message
        )
        let service = service(container)
        try service.refreshWaiting()
        let item = try #require(service.waiting.first)
        #expect(item.body.count <= 200)
        #expect(!item.body.contains("**"))
        #expect(!item.body.contains("\n"))
        #expect(item.body.hasPrefix("Prepared Full message"))
        let first = try cardFirst ? service.openInvitation(id: item.id) : service
            .openFollowUp(requestID: id)
        let second = try cardFirst ? service.openFollowUp(requestID: id) : service
            .openInvitation(id: item.id)
        #expect(first == second)
        #expect(service.waiting.isEmpty)
        let context = ModelContext(container)
        let chats = try context.fetch(FetchDescriptor<Chat>())
        #expect(chats.count == 1)
        let chat = try #require(chats.first)
        #expect(chat.spaceID == space.id)
        #expect(chat.activeFlow == nil)
        let messages = try context.fetch(FetchDescriptor<Message>())
        #expect(messages.count == 2)
        #expect(messages.filter { $0.role == "assistant" }.map(\.content) == [message])
        #expect(messages.filter(\.isCompactionSummary).count == 1)
        #expect(try context.fetchCount(FetchDescriptor<InitiativeOccurrence>()) == 0)
        context.delete(chat)
        try context.save()
        #expect(throws: (any Error).self) { try service.openFollowUp(requestID: id) }
    }

    @Test func legacyOpeningIsIdempotentButHandledLegacyCannotResurrect() throws {
        let (container, agent, space) = try fixture()
        let id = try add(container, agent: agent, due: nil)
        let handledID = try add(container, agent: agent, due: nil)
        let context = ModelContext(container)
        let handled = try #require(context.fetch(FetchDescriptor<AgentInitiativeRequest>())
            .first(where: { $0.id == handledID }))
        handled.handledAt = .now
        try context.save()
        let service = service(container)
        let chat = try service.openFollowUp(requestID: id, legacySpaceID: space.id)
        #expect(try service.openFollowUp(requestID: id) == chat)
        #expect(throws: (any Error).self) { try service.openFollowUp(requestID: handledID) }
    }

    @Test func missingScopeAndDismissalStayUnavailable() throws {
        let (container, agent, space) = try fixture()
        let invalid = try add(
            container,
            agent: agent,
            due: Date.now.addingTimeInterval(-1),
            spaceID: UUID()
        )
        let dismissed = try add(
            container,
            agent: agent,
            due: Date.now.addingTimeInterval(-1),
            spaceID: space.id
        )
        let service = service(container)
        try service.refreshWaiting()
        #expect(service.waiting.count == 1)
        try service.dismissInvitation(id: "follow-up:\(dismissed.uuidString)")
        #expect(throws: (any Error).self) { try service.openFollowUp(requestID: invalid) }
        #expect(throws: (any Error).self) { try service.openFollowUp(requestID: dismissed) }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Chat>()) == 0)
    }

    @Test func activeTimerDiscoversFollowUpWithoutNotificationDelivery() async throws {
        let (container, agent, _) = try fixture()
        try add(container, agent: agent, due: Date.now.addingTimeInterval(0.2))
        let service = service(container)
        service.isActive = true
        defer { service.setActive(false) }
        try service.refreshWaiting()
        #expect(service.waiting.isEmpty)
        try await Task.sleep(for: .seconds(1.5))
        #expect(service.waiting.count == 1)
    }

    @Test(arguments: ["open", "dismiss", "overflow"])
    func cleanupMatchesFollowUpPayloadAndPreservesOtherDeliveries(action: String) async throws {
        let (container, agent, _) = try fixture()
        let center = FakeInitiativeNotifications()
        let count = action == "overflow" ? 6 : 1
        var ids: [UUID] = []
        for index in 0 ..< count {
            let id = try add(
                container,
                agent: agent,
                due: Date.now.addingTimeInterval(-Double(index + 1) * 60)
            )
            ids.append(id)
            let content = UNMutableNotificationContent()
            content.userInfo = ["initiativeRequestID": id.uuidString]
            let identifier = "backgroundprompt-\(UUID().uuidString)"
            center.requests.append(UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            ))
            center.deliveries.append(DeliveredInitiativeNotification(
                identifier: identifier,
                date: .now,
                followUpID: id
            ))
        }
        center.requests.append(UNNotificationRequest(
            identifier: "unrelated-repeating",
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: true)
        ))
        center.deliveries.append(DeliveredInitiativeNotification(
            identifier: "unrelated",
            date: .now
        ))
        let service = InitiativeService(
            modelContainer: container,
            scheduler: InitiativeNotificationScheduler(
                notifications: center,
                authorization: FakeNotificationAuthorization(status: .denied)
            )
        )
        try service.refreshWaiting()
        if action == "open" { _ = try service.openFollowUp(requestID: ids[0]) }
        if action ==
            "dismiss" { try service.dismissInvitation(id: "follow-up:\(ids[0].uuidString)") }
        await service.cleanDeliveredNotifications()
        #expect(center.deliveries.count == (action == "overflow" ? 6 : 1))
        #expect(center.requests.count == (action == "overflow" ? 6 : 1))
        #expect(center.requests.contains { $0.identifier == "unrelated-repeating" })
        #expect(center.deliveries.contains { $0.identifier == "unrelated" })
        #expect(!center.deliveries
            .contains { $0.followUpID == (action == "overflow" ? ids.last : ids.first) })
    }

    @Test func mixedDueTimeTiesKeepStableSurvivorsWithoutRefill() throws {
        let (container, agent, space) = try fixture()
        let due = baseline.addingTimeInterval(3600)
        for _ in 0 ..< 4 {
            let schedule = IntentSchedule(content: "Daily", frequency: .daily, hour: 1, minute: 0)
            let intent = Intent(agentID: agent.id, content: "Routine", schedules: [schedule])
            container.mainContext.insert(intent)
            container.mainContext.insert(IntentInitiative(
                intentID: intent.id,
                scheduleID: schedule.id,
                instructions: "Help",
                notificationBody: "Recurring"
            ))
        }
        var followUpIDs: [String] = []
        for _ in 0 ..< 3 {
            let id = try add(container, agent: agent, due: due, spaceID: space.id)
            followUpIDs.append("follow-up:\(id.uuidString)")
        }
        let context = ModelContext(container)
        try WaitingInitiativeStore.reconcile(context: context, now: baseline, calendar: calendar)
        try WaitingInitiativeStore.reconcile(context: context, now: due, calendar: calendar)
        let kept = try WaitingMessageStore.messages(context: context, now: due)
        #expect(kept.count == 5)
        #expect(kept.allSatisfy { $0.dueAt == due })
        let recurringIDs = try context.fetch(FetchDescriptor<IntentInitiative>())
            .map { $0.id.uuidString }.sorted()
        let retainedRecurringIDs = kept.compactMap { item -> String? in
            guard case .recurring(let id) = item.source else { return nil }
            return String(id.prefix(36))
        }
        #expect(kept.prefix(3).map(\.id) == followUpIDs.sorted())
        #expect(retainedRecurringIDs == Array(recurringIDs.prefix(2)))
        let fresh = ModelContext(container)
        try WaitingInitiativeStore.reconcile(context: fresh, now: due, calendar: calendar)
        #expect(try WaitingMessageStore.messages(context: fresh, now: due).map(\.id) == kept
            .map(\.id))
        for item in kept {
            switch item.source {
            case .recurring(let id): try WaitingInitiativeStore.dismiss(id: id, context: fresh)
            case .followUp(let id): _ = try WaitingMessageStore.openFollowUp(
                    id: id,
                    context: fresh,
                    now: due
                )
            }
        }
        let reopened = ModelContext(container)
        try WaitingInitiativeStore.reconcile(
            context: reopened,
            now: due.addingTimeInterval(1),
            calendar: calendar
        )
        #expect(try WaitingMessageStore.messages(context: reopened, now: due.addingTimeInterval(1))
            .isEmpty)
    }

    private func service(_ container: ModelContainer) -> InitiativeService {
        InitiativeService(
            modelContainer: container,
            scheduler: InitiativeNotificationScheduler(
                notifications: FakeInitiativeNotifications(),
                authorization: FakeNotificationAuthorization(status: .denied)
            )
        )
    }
}
