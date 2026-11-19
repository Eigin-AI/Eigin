import Foundation
import SwiftData

/// Loads a bounded, access-scoped preview for an unscheduled reflection.
@MainActor
enum ReflectionContext {
    private struct Outreach {
        let id: String
        let date: Date
        let text: String
    }

    static func load(
        container: ModelContainer, agentID: UUID, accessPolicy: SpaceAccessPolicy,
        permissionPolicy: any ToolPermissionPolicy, now: Date = .now, calendar: Calendar = .current
    ) throws -> String {
        let context = ModelContext(container)
        let since = now.addingTimeInterval(-7 * 86400)
        let horizon = now.addingTimeInterval(7 * 86400)
        func allows(_ capability: ToolCapability) -> Bool {
            permissionPolicy.permissionLevel(for: capability.key) == .always
        }
        let readsChats = [
            ListChatsTool.capability,
            GetChatTranscriptTool.capability,
            SearchChatTranscriptTool.capability,
        ].allSatisfy(allows)
        let readsKnowledge = [SearchKnowledgeTool.capability, GetKnowledgeTool.capability]
            .allSatisfy(allows)
        let readsIntents = allows(ListIntentsTool.capability)
        let intents = try context.fetch(FetchDescriptor<Intent>(
            predicate: #Predicate { $0.agentID == agentID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )).filter { $0.isActive && accessPolicy.canAccess(itemSpaceID: $0.spaceID) }
        let agreements = try context.fetch(FetchDescriptor<IntentInitiative>())
        var scheduledIDs = Set<UUID>()
        var upcoming: [Outreach] = []
        for intent in intents {
            for agreement in agreements where agreement.enabled && agreement.intentID == intent.id {
                guard let schedule = intent.schedules
                    .first(where: { $0.id == agreement.scheduleID }),
                    (try? InitiativeRecurrenceCompiler.validate(schedule)) != nil,
                    let date = schedule.nextOccurrence(onOrAfter: now, calendar: calendar)
                else { continue }
                scheduledIDs.insert(intent.id)
                if date < horizon {
                    upcoming.append(Outreach(
                        id: occurrenceKey(agreement.id, date), date: date,
                        text: readsIntents
                            ? "scheduled initiative intent \(intent.id): \(clip(agreement.notificationBody, 120)); \(clip(agreement.instructions, 200))"
                            : "scheduled initiative (details withheld by permissions)"
                    ))
                }
            }
        }

        // History and schedules are required: a failed read must not look like an empty history.
        let historyDescriptor = FetchDescriptor<AgentInitiativeRequest>(
            predicate: #Predicate {
                $0.agentID == agentID && $0.handledAt == nil
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse), SortDescriptor(\.id)]
        )
        let handledDescriptor = FetchDescriptor<AgentInitiativeRequest>(
            predicate: #Predicate {
                $0.agentID == agentID && $0.handledAt != nil
            },
            sortBy: [SortDescriptor(\.handledAt, order: .reverse), SortDescriptor(\.id)]
        )
        let pendingDescriptor = FetchDescriptor<AgentInitiativeRequest>(
            predicate: #Predicate {
                $0.agentID == agentID && $0.handledAt == nil && $0.disposition == nil
                    && $0.dueAt != nil
            },
            sortBy: [SortDescriptor(\.dueAt), SortDescriptor(\.id)]
        )
        let history = try scoped(historyDescriptor, context: context, limit: 10) {
            accessPolicy
                .canAccess(itemSpaceID: $0.spaceID) &&
                ($0.handledAt != nil || $0.disposition != nil || $0.dueAt == nil)
        }
        let pendingRequests = try scoped(pendingDescriptor, context: context, limit: 10) {
            accessPolicy.canAccess(itemSpaceID: $0.spaceID)
        }
        let handledHistory = try scoped(handledDescriptor, context: context, limit: 10) {
            accessPolicy.canAccess(itemSpaceID: $0.spaceID)
        }
        let requests = history + handledHistory + pendingRequests
        var past: [Outreach] = []
        var pending: [Outreach] = []
        for request in requests {
            let due = request.dueAt ?? request.createdAt
            let state = request.disposition ?? (request.handledAt == nil ? "pending" : "handled")
            let text = "reflection/follow-up \(state): \(clip(request.title ?? "", 80)) \(clip(request.message, 320))"
                + (request.handledAt.map { " handled \($0.ISO8601Format())" } ?? "")
            let item = Outreach(id: request.id.uuidString, date: due, text: text)
            if request.handledAt == nil, request.disposition == nil, request.dueAt != nil {
                pending.append(item)
            } else {
                past.append(Outreach(
                    id: item.id,
                    date: request.handledAt ?? request.createdAt,
                    text: text
                ))
            }
        }
        let waiting = try scoped(FetchDescriptor<WaitingInitiative>(
            predicate: #Predicate { $0.agentID == agentID && $0.dueAt <= now },
            sortBy: [SortDescriptor(\.dueAt), SortDescriptor(\.id)]
        ), context: context, limit: 10) { accessPolicy.canAccess(itemSpaceID: $0.spaceID) }
        for item in waiting {
            pending.append(Outreach(
                id: occurrenceKey(item.initiativeID, item.dueAt),
                date: item.dueAt,
                text: readsIntents ? "waiting scheduled invitation: \(clip(item.body, 400))"
                    : "waiting scheduled invitation (details withheld by permissions)"
            ))
        }
        let occurrences = try scoped(FetchDescriptor<InitiativeOccurrence>(
            sortBy: [SortDescriptor(\.deliveredAt, order: .reverse), SortDescriptor(\.id)]
        ), context: context, limit: 10) { occurrence in
            let chatID = occurrence.chatID
            let descriptor = FetchDescriptor<Chat>(predicate: #Predicate { $0.id == chatID })
            guard let chat = try context.fetch(descriptor).first else { return false }
            return chat.agentID == agentID && accessPolicy.canAccess(itemSpaceID: chat.spaceID)
        }
        for occurrence in occurrences {
            let chatID = occurrence.chatID
            let descriptor = FetchDescriptor<Chat>(predicate: #Predicate { $0.id == chatID })
            guard let chat = try context.fetch(descriptor).first,
                  chat.agentID == agentID, accessPolicy.canAccess(itemSpaceID: chat.spaceID)
            else { continue }
            let topics = (readsIntents ? intents : [])
                .filter { occurrence.intentIDs.contains($0.id) }.map { clip(
                    $0.content,
                    120
                ) }
            let output = try (readsChats ? occurrence.outputMessageIDs : []).prefix(2)
                .compactMap { messageID -> String? in
                    let descriptor =
                        FetchDescriptor<Message>(predicate: #Predicate { $0.id == messageID })
                    guard let message = try context.fetch(descriptor).first,
                          message.chat?.id == chatID, message.role == "assistant",
                          !message.isCompactionSummary
                    else { return nil }
                    return clip(ChatTags.stripAll(from: message.content), 240)
                }.joined(separator: " ")
            past.append(Outreach(
                id: occurrence.id, date: occurrence.deliveredAt,
                text: "opened scheduled initiative chat \(chatID): \(readsChats ? clip(chat.title, 100) : "") \(topics.joined(separator: "; ")) \(output)"
            ))
        }

        let pendingText = section(render(pending + upcoming, newestFirst: false), budget: 3200)
        let pastText = section(render(past, newestFirst: true), budget: 3200)
        let eligible = (readsIntents ? intents : []).filter { !scheduledIDs.contains($0.id) }
            .prefix(10).map { intent in
                let tasks = intent.tasks.filter { !$0.completed }.prefix(3)
                    .map { clip($0.content, 100) }.joined(separator: "; ")
                return "intent \(intent.id): \(clip(intent.content, 350)) Tasks: \(tasks)"
            }
        let eligibleText = section(Array(eligible), budget: 2500)
        let excluded = intents.filter { scheduledIDs.contains($0.id) }
            .map { "\($0.id): \(readsIntents ? clip($0.content, 100) : "")" }
        let excludedText = section(excluded, budget: 1000)
        let chatText: String
        if !readsChats {
            chatText = "withheld by permissions"
        } else { do {
            let chats = try recentChats(
                context: context,
                agentID: agentID,
                since: since,
                accessPolicy: accessPolicy
            )
            let previews = try chats.map { chat in
                let excerpts = try messages(chatID: chat.id, context: context, limit: 4).reversed()
                    .map {
                        "\($0.role) \($0.timestamp.ISO8601Format()): \(clip(ChatTags.stripAll(from: $0.content), 90))"
                    }
                return "chat \(chat.id) \(clip(chat.title, 120))\n" + excerpts
                    .joined(separator: "\n")
            }
            chatText = section(previews, budget: 3200)
        } catch {
            chatText = "unavailable"
        } }
        let knowledgeText: String
        if !readsKnowledge {
            knowledgeText = "withheld by permissions"
        } else { do {
            // Reuse knowledge's scope and shadowing semantics rather than selecting raw source
            // rows.
            let knowledge = DefaultKnowledgeService(modelContainer: container)
            let entries = try knowledge.recentSources(
                since: since, agentID: agentID, accessPolicy: accessPolicy, limit: 10
            )
            knowledgeText = section(Array(entries), budget: 1800)
        } catch {
            knowledgeText = "unavailable"
        } }
        return clip(Prompt.Background.reflectionPreview(
            asOf: now.ISO8601Format(), pendingOutreach: pendingText, previousOutreach: pastText,
            unscheduledIntents: eligibleText, scheduledIntents: excludedText,
            recentChats: chatText, recentKnowledge: knowledgeText
        ), 16000)
    }

    private static func scoped<T: PersistentModel>(
        _ input: FetchDescriptor<T>, context: ModelContext, limit: Int,
        include: (T) throws -> Bool
    ) throws -> [T] {
        var descriptor = input
        descriptor.fetchLimit = 25
        var result: [T] = []
        while result.count < limit {
            let page = try context.fetch(descriptor)
            result += try page.filter(include).prefix(limit - result.count)
            if page.count < 25 { break }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + page.count
        }
        return result
    }

    private static func occurrenceKey(_ initiativeID: UUID, _ dueAt: Date) -> String {
        "\(initiativeID):\(Int64(dueAt.timeIntervalSince1970))"
    }

    private static func render(_ items: [Outreach], newestFirst: Bool) -> [String] {
        var seen = Set<String>()
        return items.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return newestFirst ? $0.date > $1.date : $0.date < $1.date
        }.filter { seen.insert($0.id).inserted }.prefix(10).map {
            "\($0.date.ISO8601Format()) [\($0.id)] \($0.text)"
        }
    }

    private static func recentChats(
        context: ModelContext, agentID: UUID, since: Date, accessPolicy: SpaceAccessPolicy
    ) throws -> [Chat] {
        var descriptor = FetchDescriptor<Chat>(
            predicate: #Predicate { $0.agentID == agentID && $0.updatedAt >= since },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.id)]
        )
        descriptor.fetchLimit = 20
        var result: [Chat] = []
        while result.count < 5 {
            let page = try context.fetch(descriptor)
            result += page.filter { accessPolicy.canAccess(itemSpaceID: $0.spaceID) }
                .prefix(5 - result.count)
            if page.count < 20 { break }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + page.count
        }
        return result
    }

    private static func messages(
        chatID: UUID,
        context: ModelContext,
        limit: Int
    ) throws -> [Message] {
        var descriptor = FetchDescriptor<Message>(
            predicate: #Predicate {
                $0.chat?.id == chatID && ($0.role == "user" || $0.role == "assistant")
                    && !$0.isCompactionSummary && $0.content != ""
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.id)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    private static func section(_ lines: [String], budget: Int) -> String {
        clip(
            lines.isEmpty ? "None found in this preview." : lines.joined(separator: "\n"),
            budget
        )
    }

    private static func clip(_ value: String, _ limit: Int) -> String {
        value.count > limit ? String(value.prefix(max(0, limit - 14))) + " …[truncated]" : value
    }
}
