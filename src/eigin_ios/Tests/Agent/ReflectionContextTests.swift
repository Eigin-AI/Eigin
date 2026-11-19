@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing

@Suite("Reflection context")
@MainActor
struct ReflectionContextTests {
    private func store() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test func previewScopesBeforeLimitingAndBoundsText() throws {
        let container = try store()
        let context = container.mainContext
        let agentID = UUID()
        let publicID = UUID()
        let privateID = UUID()
        let now = Date.now
        for index in 0 ..< 30 {
            let chat = Chat(agentID: agentID, spaceID: privateID, title: "PRIVATE CHAT")
            chat.updatedAt = now.addingTimeInterval(Double(index))
            context.insert(chat)
        }
        for index in 0 ..< 7 {
            let chat = Chat(agentID: agentID, spaceID: publicID, title: "Visible chat \(index)")
            chat.updatedAt = now.addingTimeInterval(-Double(index))
            context.insert(chat)
            for role in ["system", "tool", "user", "assistant"] {
                let message = Message(
                    role: role,
                    content: role == "user" || role == "assistant"
                        ? "Visible excerpt " + String(repeating: "x", count: 1000) : "HIDDEN BRIEFING"
                )
                message.chat = chat
                context.insert(message)
            }
        }
        let other = Chat(agentID: UUID(), title: "OTHER AGENT")
        context.insert(other)
        for (spaceID, owner, text) in [
            (nil, nil, "GLOBAL KNOWLEDGE"),
            (publicID, agentID, "AGENT KNOWLEDGE"),
            (privateID, agentID, "PRIVATE KNOWLEDGE"),
            (nil, UUID(), "OTHER KNOWLEDGE"),
        ] as [(UUID?, UUID?, String)] {
            context.insert(FirmSource(
                path: "knowledge/fact/\(text).firm",
                content: text,
                spaceID: spaceID,
                agentID: owner
            ))
        }
        try context.save()
        let preview = try ReflectionContext.load(
            container: container, agentID: agentID,
            accessPolicy: SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [publicID]),
            permissionPolicy: AlwaysAllowPolicy(), now: now
        )
        #expect(preview.contains("Visible chat 4"))
        #expect(!preview.contains("Visible chat 5"))
        #expect(preview.contains("Visible excerpt"))
        #expect(preview.contains("GLOBAL KNOWLEDGE"))
        #expect(preview.contains("AGENT KNOWLEDGE"))
        for hidden in [
            "PRIVATE CHAT",
            "HIDDEN BRIEFING",
            "OTHER AGENT",
            "PRIVATE KNOWLEDGE",
            "OTHER KNOWLEDGE",
        ] {
            #expect(!preview.contains(hidden))
        }
        #expect(preview.count <= 16000)
    }

    @Test func onlySupportedScheduleAgreementsExcludeGoals() throws {
        let container = try store()
        let context = container.mainContext
        let agentID = UUID()
        let schedule = IntentSchedule(
            content: "Weekly",
            frequency: .weekly,
            weekdays: [2],
            hour: 9,
            minute: 0
        )
        let monthly = IntentSchedule(
            content: "Monthly",
            frequency: .monthly,
            monthDays: [1],
            hour: 9,
            minute: 0
        )
        let unsupported = Intent(
            agentID: agentID,
            content: "Unsupported monthly agreement",
            schedules: [monthly]
        )
        let untimed = IntentSchedule(content: "Untimed", frequency: .daily)
        let missingTime = Intent(
            agentID: agentID,
            content: "Untimed agreement",
            schedules: [untimed]
        )
        context.insert(unsupported)
        context.insert(missingTime)
        for (intent, invalidSchedule) in [(unsupported, monthly), (missingTime, untimed)] {
            context.insert(IntentInitiative(
                intentID: intent.id,
                scheduleID: invalidSchedule.id,
                instructions: "Invalid plan",
                notificationBody: "Invalid"
            ))
        }
        let scheduled = Intent(agentID: agentID, content: "Scheduled goal", schedules: [schedule])
        let unscheduled = Intent(agentID: agentID, content: "Unscheduled goal")
        let disabled = Intent(
            agentID: agentID,
            content: "Disabled agreement",
            schedules: [schedule]
        )
        let invalid = Intent(agentID: agentID, content: "Missing schedule")
        for intent in [scheduled, unscheduled, disabled, invalid] {
            context.insert(intent)
        }
        for intent in [scheduled, disabled, invalid] {
            let agreement = IntentInitiative(
                intentID: intent.id,
                scheduleID: schedule.id,
                instructions: "Scheduled instructions",
                notificationBody: "Invitation"
            )
            agreement.enabled = intent.id != disabled.id
            context.insert(agreement)
        }
        try context.save()
        let now = try #require(ISO8601DateFormatter().date(from: "2026-01-10T12:00:00Z"))
        let preview = try ReflectionContext.load(
            container: container,
            agentID: agentID,
            accessPolicy: .init(currentSpaceID: nil, publicSpaceIDs: []),
            permissionPolicy: AlwaysAllowPolicy(), now: now
        )
        let eligible = String(preview.components(separatedBy: "## Unscheduled active intents")[1]
            .components(separatedBy: "## Scheduled intents")[0])
        #expect(!eligible.contains("Scheduled goal"))
        #expect(eligible.contains("Unscheduled goal"))
        #expect(eligible.contains("Disabled agreement"))
        #expect(eligible.contains("Missing schedule"))
        #expect(eligible.contains("Unsupported monthly agreement"))
        #expect(eligible.contains("Untimed agreement"))
        #expect(preview.contains("Scheduled goal"))
    }

    @Test func weeklyAgreementBeyond168HoursStillExcludesGoal() throws {
        let container = try store()
        let context = container.mainContext
        let agentID = UUID()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Copenhagen"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-18T07:00:01Z"))
        let schedule = IntentSchedule(
            content: "Sunday",
            frequency: .weekly,
            weekdays: [1],
            hour: 9,
            minute: 0
        )
        let due = try #require(schedule.nextOccurrence(onOrAfter: now, calendar: calendar))
        #expect(due.timeIntervalSince(now) > 7 * 86400)
        let goal = Intent(
            agentID: agentID,
            content: "Goal beyond the horizon",
            schedules: [schedule]
        )
        context.insert(goal)
        context.insert(IntentInitiative(
            intentID: goal.id,
            scheduleID: schedule.id,
            instructions: "Future scheduled instructions",
            notificationBody: "Future scheduled body"
        ))
        try context.save()
        let preview = try ReflectionContext.load(
            container: container,
            agentID: agentID,
            accessPolicy: .init(
                currentSpaceID: nil,
                publicSpaceIDs: []
            ),
            permissionPolicy: AlwaysAllowPolicy(),
            now: now,
            calendar: calendar
        )
        let sections = preview.components(separatedBy: "## Scheduled intents")
        #expect(!sections[0].contains("Goal beyond the horizon"))
        #expect(sections[1].contains("Goal beyond the horizon"))
        #expect(!preview.contains("Future scheduled instructions"))
    }

    @Test func outreachSpansPastPendingAndScheduledMessages() throws {
        let container = try store()
        let context = container.mainContext
        let agentID = UUID()
        let now = Date.now
        let dismissed = AgentInitiativeRequest(agentID: agentID, message: "Dismissed suggestion")
        dismissed.disposition = "dismissed"
        dismissed.createdAt = now.addingTimeInterval(-30 * 86400)
        dismissed.handledAt = now.addingTimeInterval(-29 * 86400)
        let pending = AgentInitiativeRequest(agentID: agentID, message: "Upcoming follow-up")
        pending.dueAt = now.addingTimeInterval(30 * 86400)
        context.insert(dismissed)
        context.insert(pending)
        let chat = Chat(agentID: agentID, title: "Prior scheduled conversation")
        context.insert(chat)
        let savedOutput = Message(role: "assistant", content: "Saved scheduled finding")
        savedOutput.chat = chat
        savedOutput.timestamp = now.addingTimeInterval(-3600)
        context.insert(savedOutput)
        let briefing = Message(role: "assistant", content: "HIDDEN SUMMARY")
        briefing.isCompactionSummary = true
        briefing.chat = chat
        context.insert(briefing)
        for index in 0 ..< 5 {
            let continuation = Message(
                role: "assistant",
                content: "Later unrelated continuation \(index)"
            )
            continuation.chat = chat
            context.insert(continuation)
        }
        let occurrence = InitiativeOccurrence(
            id: "opened",
            registrationID: "registration",
            deliveredAt: now.addingTimeInterval(-3600),
            chatID: chat.id,
            intentIDs: []
        )
        occurrence.outputMessageIDs = [savedOutput.id, briefing.id]
        context.insert(occurrence)
        context.insert(WaitingInitiative(
            id: "waiting",
            initiativeID: UUID(),
            revision: "r",
            agentID: agentID,
            spaceID: nil,
            dueAt: now,
            registrationID: "r",
            body: "Due invitation"
        ))
        let schedule = IntentSchedule(content: "Daily", frequency: .daily, hour: 9, minute: 0)
        let intent = Intent(agentID: agentID, content: "Scheduled topic", schedules: [schedule])
        context.insert(intent)
        context.insert(IntentInitiative(
            intentID: intent.id,
            scheduleID: schedule.id,
            instructions: "Future scheduled work",
            notificationBody: "Invite"
        ))
        try context.save()
        let preview = try ReflectionContext.load(
            container: container,
            agentID: agentID,
            accessPolicy: .init(currentSpaceID: nil, publicSpaceIDs: []),
            permissionPolicy: AlwaysAllowPolicy(), now: now
        )
        #expect(preview.contains("Saved scheduled finding"))
        #expect(!preview.contains("HIDDEN SUMMARY"))
        for topic in [
            "dismissed",
            "Dismissed suggestion",
            "Upcoming follow-up",
            "Prior scheduled conversation",
            "Due invitation",
            "Future scheduled work",
        ] {
            #expect(preview.contains(topic))
        }
    }

    @Test func waitingPreviewOmitsFutureRowsAndDeduplicatesDueOccurrences() throws {
        let container = try store()
        let context = container.mainContext
        let agentID = UUID()
        let now = Date.now
        let schedule = IntentSchedule(content: "Daily", frequency: .daily, hour: 9, minute: 0)
        let goal = Intent(agentID: agentID, content: "Daily goal", schedules: [schedule])
        let agreement = IntentInitiative(
            intentID: goal.id,
            scheduleID: schedule.id,
            instructions: "Upcoming current plan",
            notificationBody: "Current invitation"
        )
        context.insert(goal)
        context.insert(agreement)
        let next = try #require(schedule.nextOccurrence(onOrAfter: now))
        context.insert(WaitingInitiative(
            id: "future",
            initiativeID: agreement.id,
            revision: "r",
            agentID: agentID,
            spaceID: nil,
            dueAt: next,
            registrationID: "r",
            body: "FUTURE WAITING ROW"
        ))
        for revision in ["r1", "r2"] {
            context.insert(WaitingInitiative(
                id: revision,
                initiativeID: agreement.id,
                revision: revision,
                agentID: agentID,
                spaceID: nil,
                dueAt: now,
                registrationID: revision,
                body: "Due invitation topic"
            ))
        }
        try context.save()
        let preview = try ReflectionContext.load(
            container: container,
            agentID: agentID,
            accessPolicy: .init(
                currentSpaceID: nil,
                publicSpaceIDs: []
            ),
            permissionPolicy: AlwaysAllowPolicy(),
            now: now
        )
        #expect(!preview.contains("FUTURE WAITING ROW"))
        #expect(preview.contains("Upcoming current plan"))
        #expect(preview.components(separatedBy: "Due invitation topic").count == 2)
    }

    @Test func deniedNotificationsStillSaveOpenAndDismissReflections() async throws {
        let container = try store()
        let context = container.mainContext
        let provider = Provider(name: "Test", baseURL: "https://model.test")
        let agent = Agent(name: "Test", providerID: provider.id, model: "test")
        agent.proactivity = .balanced
        context.insert(provider)
        context.insert(agent)
        try context.save()
        let now = Date.now
        let due = now.addingTimeInterval(3600)
        let args = [
            "notification_title": "A connection",
            "message": "Concrete useful finding",
            "summary": "Evidence and next steps",
            "deliver_at": due.ISO8601Format(),
        ]
        let call = try ToolCall(id: "reflection", type: "function", function: .init(
            name: "background_notify", arguments: String(
                decoding: JSONEncoder().encode(args),
                as: UTF8.self
            )
        ))
        let model = FakeChatService()
        model.enqueueEventStream([.toolCall(call), .finished(.toolCalls)])
        let center = FakeLocalNotificationCenter()
        var authorizationAttempts = 0
        let scheduler = DefaultFollowUpScheduler(
            now: { now }, container: container, notificationCenter: center,
            authorize: { canPrompt in
                authorizationAttempts += 1
                #expect(!canPrompt)
                return false
            }
        )
        #expect(await runReflection(
            container: container, model: model, scheduler: scheduler
        ))
        #expect(authorizationAttempts == 1)
        #expect(center.requests.isEmpty)
        let saved = try #require(context.fetch(FetchDescriptor<AgentInitiativeRequest>()).first)
        let message = try #require(args["message"])
        let summary = try #require(args["summary"])
        #expect(try WaitingMessageStore.messages(context: context, now: now).isEmpty)
        let later = due.addingTimeInterval(1)
        #expect(try WaitingMessageStore.messages(context: context, now: later).count == 1)
        let chatID = try WaitingMessageStore.openFollowUp(
            id: saved.id,
            context: context,
            now: later
        )
        let chat = try #require(context.fetch(FetchDescriptor<Chat>()).first { $0.id == chatID })
        #expect(chat.messages.contains { $0.role == "assistant" && $0.content == message })
        #expect(chat.messages.contains { $0.isCompactionSummary && $0.content.contains(summary) })
        #expect(try WaitingMessageStore.openFollowUp(
            id: saved.id,
            context: context,
            now: later
        ) == chatID)

        let dismissed = AgentInitiativeRequest(agentID: agent.id, message: "Do not repeat this")
        dismissed.dueAt = now
        context.insert(dismissed)
        try context.save()
        try WaitingMessageStore.dismissFollowUp(id: dismissed.id, context: context, now: later)
        let preview = try ReflectionContext.load(
            container: container,
            agentID: agent.id,
            accessPolicy: .init(
                currentSpaceID: nil,
                publicSpaceIDs: []
            ),
            permissionPolicy: AlwaysAllowPolicy(), now: later
        )
        #expect(preview.contains("dismissed:  Do not repeat this"))
    }

    @Test func silentReflectionLoopCreatesNothing() async throws {
        let container = try store()
        let provider = Provider(name: "Test", baseURL: "https://model.test")
        let agent = Agent(name: "Test", providerID: provider.id, model: "test")
        agent.proactivity = .balanced
        container.mainContext.insert(provider)
        container.mainContext.insert(agent)
        try container.mainContext.save()
        let model = FakeChatService()
        model.enqueueEventStream([.contentDelta("Nothing useful to add."), .finished(.stop)])
        #expect(await runReflection(
            container: container,
            model: model
        ))
        #expect(!model.capturedEventMessages.isEmpty)
        #expect(try container.mainContext
            .fetchCount(FetchDescriptor<AgentInitiativeRequest>()) == 0)
    }

    @Test func reactiveReflectionCreatesNoOutreach() async throws {
        let container = try store()
        let provider = Provider(name: "Test", baseURL: "https://model.test")
        let agent = Agent(name: "Test", providerID: provider.id, model: "test")
        agent.proactivity = .reactive
        container.mainContext.insert(provider)
        container.mainContext.insert(agent)
        try container.mainContext.save()
        let model = FakeChatService()
        model.enqueueEventStream([.contentDelta("Unexpected model call"), .finished(.stop)])
        #expect(await runReflection(
            container: container,
            model: model
        ))
        #expect(model.capturedEventMessages.isEmpty)
        #expect(try container.mainContext
            .fetchCount(FetchDescriptor<AgentInitiativeRequest>()) == 0)
    }

    @Test func deeperChatToolsRejectPrivateSpaceReads() async throws {
        let container = try store()
        let context = container.mainContext
        let agent = Agent(name: "Test", providerID: UUID(), model: "test")
        let privateChat = Chat(agentID: agent.id, spaceID: UUID(), title: "Private title")
        context.insert(agent)
        context.insert(privateChat)
        let message = Message(role: "user", content: "Private secret")
        message.chat = privateChat
        context.insert(message)
        try context.save()
        let policy = SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [])
        let args = "{\"chat_id\":\"\(privateChat.id)\",\"query\":\"secret\"}"
        let call = ToolCall(
            id: "read",
            type: "function",
            function: .init(name: "read", arguments: args)
        )
        let read = await GetChatTranscriptTool(accessPolicy: policy).execute(call, agent: agent)
        let search = await SearchChatTranscriptTool(accessPolicy: policy).execute(
            call,
            agent: agent
        )
        let list = await ListChatsTool(accessPolicy: policy).execute(call, agent: agent)
        #expect(read.isError)
        #expect(search.isError)
        #expect(!list.content.contains("Private title"))
        #expect(!read.content.contains("Private secret"))
    }

    @Test func recentDismissalOfAnOldRequestSurvivesHistoryLimit() throws {
        let container = try store()
        let context = container.mainContext
        let agentID = UUID()
        let now = Date.now
        let old = AgentInitiativeRequest(
            agentID: agentID,
            message: "Recently dismissed old suggestion"
        )
        old.createdAt = now.addingTimeInterval(-30 * 86400)
        old.handledAt = now
        old.disposition = "dismissed"
        context.insert(old)
        for index in 0 ..< 20 {
            let request = AgentInitiativeRequest(
                agentID: agentID,
                message: "Earlier handled message \(index)"
            )
            request.createdAt = now.addingTimeInterval(-3600)
            request.handledAt = now.addingTimeInterval(-1800 - Double(index))
            request.disposition = "opened"
            context.insert(request)
        }
        try context.save()
        let preview = try ReflectionContext.load(
            container: container,
            agentID: agentID,
            accessPolicy: .init(
                currentSpaceID: nil,
                publicSpaceIDs: []
            ),
            permissionPolicy: AlwaysAllowPolicy(), now: now
        )
        #expect(preview.contains("Recently dismissed old suggestion"))
    }

    @Test func everySectionOverflowsWithinTheTotalBudget() throws {
        let container = try store()
        let context = container.mainContext
        let agentID = UUID()
        let now = Date.now
        let long = String(repeating: "detail ", count: 500)
        for index in 0 ..< 25 {
            let chat = Chat(agentID: agentID, title: "Chat \(index) " + long)
            chat.updatedAt = now.addingTimeInterval(-Double(index))
            context.insert(chat)
            for messageIndex in 0 ..< 6 {
                let message = Message(role: "user", content: "Message \(messageIndex) " + long)
                message.timestamp = now.addingTimeInterval(-Double(messageIndex))
                message.chat = chat
                context.insert(message)
            }
            let intent = Intent(
                agentID: agentID,
                content: "Goal \(index) " + long,
                tasks: [IntentTask(content: long)]
            )
            context.insert(intent)
            if index % 2 == 0 {
                let schedule = IntentSchedule(
                    content: "Daily",
                    frequency: .daily,
                    hour: 9,
                    minute: 0
                )
                intent.schedules = [schedule]
                context.insert(IntentInitiative(
                    intentID: intent.id,
                    scheduleID: schedule.id,
                    instructions: long,
                    notificationBody: long
                ))
            }
            let pending = AgentInitiativeRequest(
                agentID: agentID,
                message: "Pending \(index) " + long
            )
            pending.dueAt = now.addingTimeInterval(Double(index + 1) * 60)
            context.insert(pending)
            let previous = AgentInitiativeRequest(
                agentID: agentID,
                message: "Prior \(index) " + long
            )
            previous.disposition = "dismissed"
            previous.handledAt = now.addingTimeInterval(-Double(index))
            context.insert(previous)
            context.insert(FirmSource(path: "knowledge/fact/entry_\(index).firm", content: long))
        }
        try context.save()
        let preview = try ReflectionContext.load(
            container: container,
            agentID: agentID,
            accessPolicy: .init(
                currentSpaceID: nil,
                publicSpaceIDs: []
            ),
            permissionPolicy: AlwaysAllowPolicy(), now: now
        )
        #expect(preview.count <= 16000)
        #expect(preview.contains("[truncated]"))
        for heading in [
            "Pending outreach",
            "Prior outreach",
            "Unscheduled active intents",
            "Scheduled intents",
            "Recent conversation excerpts",
            "Recently saved knowledge",
        ] {
            #expect(preview.contains(heading))
        }
        #expect(!preview.contains("Message 5"))
        #expect(!preview.contains("Chat 24"))
        #expect(!preview.contains("Pending 24"))
    }

    @Test func restrictedPreviewContentNeverReachesModel() async throws {
        let container = try store()
        let context = container.mainContext
        let provider = Provider(name: "Test", baseURL: "https://model.test")
        let agent = Agent(name: "Test", providerID: provider.id, model: "test")
        agent.proactivity = .balanced
        context.insert(provider)
        context.insert(agent)
        let chat = Chat(agentID: agent.id, title: "Restricted conversation title")
        context.insert(chat)
        let message = Message(role: "user", content: "Restricted chat excerpt")
        message.chat = chat
        context.insert(message)
        context.insert(FirmSource(
            path: "knowledge/fact/restricted.firm",
            content: "Restricted knowledge excerpt"
        ))
        let schedule = IntentSchedule(content: "Daily", frequency: .daily, hour: 9, minute: 0)
        let intent = Intent(
            agentID: agent.id,
            content: "Restricted intent content",
            schedules: [schedule]
        )
        context.insert(intent)
        context.insert(IntentInitiative(
            intentID: intent.id,
            scheduleID: schedule.id,
            instructions: "Restricted schedule instructions",
            notificationBody: "Restricted schedule body"
        ))
        for (capability, level) in [
            (GetChatTranscriptTool.capability, ToolPermissionLevel.never),
            (SearchKnowledgeTool.capability, .ask),
            (ListIntentsTool.capability, .never),
        ] {
            context.insert(AgentToolGrant(agentID: agent.id, capability: capability, level: level))
        }
        try context.save()
        let model = FakeChatService()
        model.enqueueEventStream([.contentDelta("Nothing useful to add."), .finished(.stop)])
        #expect(await runReflection(
            container: container,
            model: model
        ))
        let system = try #require(model.capturedEventMessages.first { $0.role == "system" }?
            .content)
        for restricted in [
            "Restricted conversation title",
            "Restricted chat excerpt",
            "Restricted knowledge excerpt", "Restricted intent content",
            "Restricted schedule instructions",
            "Restricted schedule body",
        ] {
            #expect(!system.contains(restricted))
        }
        let tools = try #require(model.capturedEventTools)
        #expect(!tools
            .contains {
                $0.function.name == "get_chat_transcript" || $0.function.name == "search_knowledge"
            })
    }

    @Test func reflectionReadsGlobalKnowledgeAfterAPrivateTurn() async throws {
        let container = try store()
        let context = container.mainContext
        let provider = Provider(name: "Test", baseURL: "https://model.test")
        let agent = Agent(name: "Test", providerID: provider.id, model: "test")
        agent.proactivity = .balanced
        let privateSpace = Space(agentID: agent.id)
        privateSpace.isPrivate = true
        context.insert(provider)
        context.insert(agent)
        context.insert(privateSpace)
        let sourceChat = Chat(agentID: agent.id, spaceID: privateSpace.id)
        let sourceMessage = Message(role: "user", content: "Private source chat excerpt")
        sourceMessage.chat = sourceChat
        context.insert(sourceChat)
        context.insert(sourceMessage)
        try context.save()

        let knowledge = DefaultKnowledgeService(modelContainer: container)
        let spaceID = privateSpace.id
        let agentID = agent.id
        try await knowledge.rebuild(
            spaceID: spaceID,
            agentID: agentID,
            accessPolicy: .init(
                currentSpaceID: spaceID,
                publicSpaceIDs: []
            )
        )
        for (id, claim, scope) in [
            ("private_claim", "Private reflection claim", spaceID as UUID?),
            ("global_claim", "Global reflection claim", nil),
        ] {
            try await knowledge.addEntity(
                FirmEntity(
                    id: "fact.\(id)",
                    entityType: "fact",
                    fields: [FirmField(
                        name: "claim",
                        value: .string(value: claim)
                    )]
                ),
                spaceID: scope,
                agentID: agentID,
                chatID: sourceChat.id
            )
        }
        let prior = try await knowledge.getEntity(
            type: "fact",
            id: "private_claim",
            spaceID: spaceID,
            agentID: agentID
        )
        #expect(prior != nil)
        Container.shared.knowledgeService.register { knowledge }
        defer { Container.shared.knowledgeService.reset() }
        let model = FakeChatService()
        let calls = ["private_claim", "global_claim"].map { id in
            ToolCall(id: id, type: "function", function: .init(
                name: "get_knowledge",
                arguments: "{\"type\":\"fact\",\"id\":\"\(id)\",\"include_context\":true}"
            ))
        }
        model.enqueueEventStream(calls.map { .toolCall($0) } + [.finished(.toolCalls)])
        model.enqueueEventStream([.contentDelta("Nothing useful to add."), .finished(.stop)])
        #expect(await runReflection(
            container: container,
            model: model
        ))
        let privateResult = try #require(model.capturedEventMessages
            .first { $0.toolCallID == "private_claim" }?.content)
        let globalResult = try #require(model.capturedEventMessages
            .first { $0.toolCallID == "global_claim" }?.content)
        #expect(privateResult.contains("not found"))
        #expect(!privateResult.contains("Private reflection claim"))
        #expect(globalResult.contains("Global reflection claim"))
        #expect(!globalResult.contains("Private source chat excerpt"))
        #expect(!globalResult.contains(sourceChat.id.uuidString))
        let readTool = try #require(model.capturedEventTools?
            .first { $0.function.name == "get_knowledge" })
        #expect(readTool.function.parameters.properties?["include_context"] == nil)
    }

    @Test func reflectionUsesItsOwnCooldownAndPreservesExistingKeys() throws {
        let suite = "reflection-cooldown-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date.now
        #expect(BackgroundRunMode.preparation.lastRunKey == "backgroundLastRun_initiative")
        #expect(BackgroundRunMode.maintenance.lastRunKey == "backgroundLastRun_maintenance")
        #expect(BackgroundRunMode.reflection.lastRunKey == "backgroundLastRun_reflection")
        #expect(BackgroundPromptService
            .eligibleModes(now: now, defaults: defaults) == BackgroundRunMode.allCases)
        defaults.set(now, forKey: BackgroundRunMode.preparation.lastRunKey)
        defaults.set(now, forKey: BackgroundRunMode.maintenance.lastRunKey)
        defaults.set(
            now.addingTimeInterval(-6 * 3600),
            forKey: BackgroundRunMode.reflection.lastRunKey
        )
        #expect(BackgroundPromptService
            .eligibleModes(now: now, defaults: defaults) == [.reflection])
    }

    private func runReflection(
        container: ModelContainer, model: any ChatService,
        scheduler: (any FollowUpScheduling)? = nil
    ) async -> Bool {
        var saved = true
        let outcome = await BackgroundPromptService.runOpportunity(
            container: container, modeOverride: .reflection, model: model,
            coordinator: BackgroundActivityCoordinator()
        ) { result in
            guard result.didNotify else { return }
            let delivery = await BackgroundPromptScheduler.deliver(
                result,
                container: container,
                scheduler: scheduler
            )
            if case .saved = delivery {} else { saved = false }
        }
        return outcome.succeeded && saved
    }
}
