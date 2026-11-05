@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Initiative conversation continuity")
@MainActor
struct InitiativeContextSourceTests {
    @Test func afternoonReceivesMorningOutputWithoutBackgroundPreparation() async throws {
        let f = try fixture()
        let context = f.container.mainContext
        let morning = try InitiativeConversationService.open(
            registrationID: f.registrationID,
            deliveredAt: .now.addingTimeInterval(-3600),
            context: context
        )
        #expect(try InitiativeConversationService.claimStart(chatID: morning, context: context))
        #expect(try InitiativeConversationService.beginExecution(
            chatID: morning,
            messages: [],
            context: context
        ))
        let morningChat = try #require(context.fetch(FetchDescriptor<Chat>())
            .first { $0.id == morning })
        let output = Message(
            role: "assistant",
            content: "The morning news included a new research release."
        )
        output.chat = morningChat
        context.insert(output)
        InitiativeConversationService.recordOutput(output, chatID: morning, context: context)
        try InitiativeConversationService.finishExecution(
            chatID: morning,
            completed: true,
            context: context
        )
        let unrelated = Message(
            role: "assistant",
            content: String(repeating: "Unrelated later conversation. ", count: 200)
        )
        unrelated.chat = morningChat
        context.insert(unrelated)
        InitiativeConversationService.recordOutput(unrelated, chatID: morning, context: context)
        try context.save()
        let afternoon = try InitiativeConversationService.open(
            registrationID: f.registrationID,
            deliveredAt: .now,
            context: context
        )
        #expect(try InitiativeConversationService.claimStart(chatID: afternoon, context: context))
        let source = InitiativeContextSource(
            knowledgeService: PreviewKnowledgeService(),
            modelContainer: f.container
        )
        let hint = await source.render(input(chatID: afternoon, agentID: f.agent.id))
        #expect(hint?.contains("new research release") == true)
        #expect(hint?.contains("Unrelated later conversation") == false)
        #expect(hint?.contains("(completed)") == true)
        #expect(hint?.contains("current information") == true)
        #expect(hint?.contains("Fetch the news") == true)
        #expect(hint?.contains("prepared_finding") == false)

        let followup = await source.render(input(
            chatID: afternoon,
            agentID: f.agent.id,
            followup: true
        ))
        #expect(followup?.contains("Execute the tasks now") == false)
        #expect(followup?.contains("do not repeat scheduled tasks unless asked") == true)
    }

    @Test(arguments: ["chat", "output"])
    func deletedPriorHistoryIsSkipped(deleted: String) async throws {
        let f = try fixture()
        let context = f.container.mainContext
        let previousID = try InitiativeConversationService.open(
            registrationID: f.registrationID,
            deliveredAt: .now.addingTimeInterval(-3600),
            context: context
        )
        let previousChat = try #require(context.fetch(FetchDescriptor<Chat>())
            .first { $0.id == previousID })
        #expect(try InitiativeConversationService.beginExecution(
            chatID: previousID,
            messages: [],
            context: context
        ))
        let output = Message(role: "assistant", content: "Deleted prior finding")
        output.chat = previousChat
        context.insert(output)
        InitiativeConversationService.recordOutput(output, chatID: previousID, context: context)
        try InitiativeConversationService.finishExecution(
            chatID: previousID,
            completed: true,
            context: context
        )
        let currentID = try InitiativeConversationService.open(
            registrationID: f.registrationID,
            deliveredAt: .now,
            context: context
        )
        if deleted == "chat" { context.delete(previousChat) } else { context.delete(output) }
        try context.save()
        let source = InitiativeContextSource(
            knowledgeService: PreviewKnowledgeService(),
            modelContainer: f.container
        )
        let hint = await source.render(input(chatID: currentID, agentID: f.agent.id))
        #expect(hint?.contains("Fetch the news") == true)
        #expect(hint?.contains("Deleted prior finding") == false)
    }

    @Test func deletedOccurrenceChatIsNotRecreatedOnRepeatedTap() throws {
        let f = try fixture()
        let context = f.container.mainContext
        let deliveredAt = Date.now
        let chatID = try InitiativeConversationService.open(
            registrationID: f.registrationID,
            deliveredAt: deliveredAt,
            context: context
        )
        let chat = try #require(context.fetch(FetchDescriptor<Chat>()).first { $0.id == chatID })
        context.delete(chat)
        try context.save()
        #expect(throws: (any Error).self) {
            try InitiativeConversationService.open(
                registrationID: f.registrationID,
                deliveredAt: deliveredAt,
                context: context
            )
        }
        #expect(try context.fetchCount(FetchDescriptor<Chat>()) == 0)
    }

    @Test func wrongAgentAndMovedChatCannotReadInitiativeContext() async throws {
        let f = try fixture()
        let chat = try InitiativeConversationService.open(
            registrationID: f.registrationID,
            deliveredAt: .now,
            context: f.container.mainContext
        )
        let source = InitiativeContextSource(
            knowledgeService: PreviewKnowledgeService(),
            modelContainer: f.container
        )
        #expect(await source.render(input(chatID: chat, agentID: UUID())) == nil)
        #expect(await source
            .render(input(chatID: chat, agentID: f.agent.id, spaceID: UUID())) == nil)
    }

    @Test func cancelledInitialTurnNeverReceivesExecutionInstructions() async throws {
        let f = try fixture()
        let context = f.container.mainContext
        let chat = try InitiativeConversationService.open(
            registrationID: f.registrationID,
            deliveredAt: .now,
            context: context
        )
        let agreement = try #require(context.fetch(FetchDescriptor<IntentInitiative>()).first)
        agreement.enabled = false
        try context.save()
        let source = InitiativeContextSource(
            knowledgeService: PreviewKnowledgeService(),
            modelContainer: f.container
        )
        let hint = await source.render(input(chatID: chat, agentID: f.agent.id))
        #expect(hint?.contains("Do not execute") == true)
        #expect(hint?.contains("Fetch the news") == false)
    }

    @Test func longPreparationKeepsSourcesAndObservationTimeInTheHint() async throws {
        let f = try fixture()
        let context = f.container.mainContext
        let intent = try #require(context.fetch(FetchDescriptor<Intent>()).first)
        let chatID = try InitiativeConversationService.open(
            registrationID: f.registrationID,
            deliveredAt: .now,
            context: context
        )
        let knowledge = DefaultKnowledgeService(modelContainer: f.container)
        try await knowledge.addEntity(
            FirmEntity(id: "preparation.long_finding", entityType: "preparation", fields: [
                .init(
                    name: "content",
                    value: .string(value: String(repeating: "Long finding. ", count: 400))
                ),
                .init(
                    name: "intent_ids",
                    value: .list(items: [.string(value: intent.id.uuidString)])
                ),
                .init(
                    name: "sources",
                    value: .list(items: [.string(value: "https://example.com/observed-source")])
                ),
                .init(name: "observed_at", value: .dateTime(value: "2026-10-01T07:00:00Z")),
            ]),
            spaceID: nil,
            agentID: f.agent.id,
            chatID: nil
        )
        let source = InitiativeContextSource(
            knowledgeService: knowledge,
            modelContainer: f.container
        )
        let hint = try #require(await source.render(input(chatID: chatID, agentID: f.agent.id)))
        #expect(hint.contains("https://example.com/observed-source"))
        #expect(hint.contains("2026-10-01T07:00:00Z"))
        #expect(hint.count < 4000)
    }

    @Test func groupedHistoryIncludesEachIntentDespiteUnevenRecentActivity() async throws {
        let f = try fixture()
        let context = f.container.mainContext
        let newsRegistration = try #require(context.fetch(FetchDescriptor<InitiativeRegistration>())
            .first)
        let news = try JSONDecoder().decode(InitiativeDelivery.self, from: newsRegistration.payload)
        let schedule = IntentSchedule(content: "Email", frequency: .daily, hour: 7, minute: 0)
        let email = Intent(agentID: f.agent.id, content: "Email", schedules: [schedule])
        let agreement = IntentInitiative(
            intentID: email.id,
            scheduleID: schedule.id,
            instructions: "Read mail",
            notificationBody: "Time for mail"
        )
        context.insert(email)
        context.insert(agreement)
        let member = InitiativeDelivery.Member(
            initiativeID: agreement.id,
            intentID: email.id,
            schedule: schedule,
            instructions: agreement.instructions,
            body: agreement.notificationBody,
            revision: agreement.updatedAt
        )
        try context.insert(InitiativeRegistration(
            id: "email",
            payload: InitiativeDelivery(
                agentID: f.agent.id,
                spaceID: nil,
                hour: 7,
                minute: 0,
                weekday: nil,
                members: [member]
            ).encoded()
        ))
        try context.insert(InitiativeRegistration(
            id: "group",
            payload: InitiativeDelivery(
                agentID: f.agent.id,
                spaceID: nil,
                hour: 7,
                minute: 0,
                weekday: nil,
                members: news.members + [member]
            ).encoded()
        ))
        try context.save()
        func run(
            _ registration: String,
            _ text: String,
            _ offset: Double,
            completed: Bool = true
        ) throws {
            let id = try InitiativeConversationService.open(
                registrationID: registration,
                deliveredAt: Date.now.addingTimeInterval(offset),
                context: context
            )
            _ = try InitiativeConversationService.beginExecution(
                chatID: id,
                messages: [],
                context: context
            )
            let chat = try #require(context.fetch(FetchDescriptor<Chat>()).first { $0.id == id })
            let message = Message(role: "assistant", content: text)
            message.chat = chat
            context.insert(message)
            InitiativeConversationService.recordOutput(message, chatID: id, context: context)
            try InitiativeConversationService.finishExecution(
                chatID: id,
                completed: completed,
                context: context
            )
        }
        try run("email", "Email-only result", -400, completed: false)
        for index in 1 ... 3 {
            try run(
                f.registrationID,
                "News result \(index)",
                Double(-300 + index)
            )
        }
        let group = try InitiativeConversationService.open(
            registrationID: "group",
            deliveredAt: .now,
            context: context
        )
        _ = try InitiativeConversationService.claimStart(chatID: group, context: context)
        let source = InitiativeContextSource(
            knowledgeService: PreviewKnowledgeService(),
            modelContainer: f.container
        )
        let hint = try #require(await source.render(input(chatID: group, agentID: f.agent.id)))
        #expect(hint.contains("Email-only result"))
        #expect(hint.contains("(partial)"))
        for index in 1 ... 3 {
            #expect(hint.contains("News result \(index)"))
        }
    }

    private func input(
        chatID: UUID,
        agentID: UUID,
        spaceID: UUID? = nil,
        followup: Bool = false
    ) -> SystemHintInput {
        SystemHintInput(
            agentID: agentID, bootstrapComplete: true, needsCompaction: false, hasSpaces: false,
            messages: followup ? [
                ChatMessage(role: "assistant", content: "News"),
                ChatMessage(role: "user", content: "Thanks"),
            ] : [],
            space: nil, spaceID: spaceID, language: nil, mode: .text,
            activeIntents: [], activeSkills: [], availableSkills: [], activeFlow: nil,
            provider: ProviderSnapshot(name: "Test", baseURL: "https://example.com"),
            modelID: "test", isSmallContext: false, chatID: chatID
        )
    }

    private func fixture() throws
        -> (container: ModelContainer, agent: Agent, registrationID: String)
    {
        let container = try ModelContainer(
            for: Schema(SchemaV12.models, version: SchemaV12.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Test", providerID: UUID(), model: "test")
        let schedule = IntentSchedule(content: "News", frequency: .daily, hour: 7, minute: 0)
        let intent = Intent(agentID: agent.id, content: "News", schedules: [schedule])
        let agreement = IntentInitiative(
            intentID: intent.id,
            scheduleID: schedule.id,
            instructions: "Fetch the news",
            notificationBody: "Time for news"
        )
        let delivery = InitiativeDelivery(
            agentID: agent.id,
            spaceID: nil,
            hour: 7,
            minute: 0,
            weekday: nil,
            members: [
                .init(
                    initiativeID: agreement.id,
                    intentID: intent.id,
                    schedule: schedule,
                    instructions: agreement.instructions,
                    body: agreement.notificationBody,
                    revision: agreement.updatedAt
                ),
            ]
        )
        let registration = try InitiativeRegistration(id: "test", payload: delivery.encoded())
        container.mainContext.insert(agent)
        container.mainContext.insert(intent)
        container.mainContext.insert(agreement)
        container.mainContext.insert(registration)
        try container.mainContext.save()
        return (container, agent, registration.id)
    }
}
