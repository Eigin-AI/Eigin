import Foundation
import SwiftData

/// Identifies the distinct opening behavior of each waiting message.
enum WaitingMessageSource {
    case recurring(occurrenceID: String)
    case followUp(requestID: UUID)

    var id: String {
        switch self {
        case .recurring(let id): "recurring:\(id)"
        case .followUp(let id): "follow-up:\(id.uuidString)"
        }
    }
}

/// Committed presentation data shared by both agent headers.
struct WaitingMessage: Identifiable {
    let source: WaitingMessageSource
    let agentID: UUID
    let dueAt: Date
    let body: String
    var id: String {
        source.id
    }
}

/// Combines due recurring invitations and prepared follow-ups under one retention policy.
@MainActor enum WaitingMessageStore {
    static func validScope(agentID: UUID, spaceID: UUID?, context: ModelContext) throws -> Bool {
        guard try context.fetch(FetchDescriptor<Agent>()).contains(where: { $0.id == agentID })
        else {
            return false
        }
        guard let spaceID else { return true }
        return try context.fetch(FetchDescriptor<Space>()).contains {
            $0.id == spaceID && $0.agentID == agentID
        }
    }

    static func messages(context: ModelContext, now: Date = .now) throws -> [WaitingMessage] {
        let recurring = try context.fetch(FetchDescriptor<WaitingInitiative>())
            .filter { $0.dueAt <= now }.map {
                WaitingMessage(
                    source: .recurring(occurrenceID: $0.id),
                    agentID: $0.agentID,
                    dueAt: $0.dueAt,
                    body: $0.body
                )
            }
        let followUps = try context.fetch(FetchDescriptor<AgentInitiativeRequest>())
            .compactMap { request -> WaitingMessage? in
                guard request.handledAt == nil, request.disposition == nil,
                      let due = request.dueAt, due <= now else { return nil }
                return WaitingMessage(
                    source: .followUp(requestID: request.id),
                    agentID: request.agentID,
                    dueAt: due,
                    body: preview(request.message)
                )
            }
        return (recurring + followUps).sorted {
            $0.dueAt == $1.dueAt ? $0.id < $1.id : $0.dueAt > $1.dueAt
        }
    }

    /// Mutates the caller's transaction; discovery and overflow commit together.
    static func retain(context: ModelContext, now: Date) throws -> Date? {
        let requests = try context.fetch(FetchDescriptor<AgentInitiativeRequest>())
        var nextDue: Date?
        for request in requests where request.handledAt == nil && request.disposition == nil {
            guard request.dueAt != nil else { continue }
            guard try validScope(
                agentID: request.agentID,
                spaceID: request.spaceID,
                context: context
            ) else {
                request.disposition = "discarded"
                request.handledAt = now
                continue
            }
            if let due = request.dueAt, due > now { nextDue = min(nextDue ?? due, due) }
        }
        let recurring = try context.fetch(FetchDescriptor<WaitingInitiative>())
        var counts: [UUID: Int] = [:]
        for item in try messages(context: context, now: now) {
            counts[item.agentID, default: 0] += 1
            guard counts[item.agentID, default: 0] > 5 else { continue }
            switch item.source {
            case .recurring(let id):
                if let record = recurring.first(where: { $0.id == id }) { context.delete(record) }
            case .followUp(let id):
                if let request = requests.first(where: { $0.id == id }) {
                    request.disposition = "discarded"
                    request.handledAt = now
                }
            }
        }
        return nextDue
    }

    static func dismissFollowUp(id: UUID, context: ModelContext, now: Date = .now) throws {
        guard let request = try context.fetch(FetchDescriptor<AgentInitiativeRequest>())
            .first(where: { $0.id == id }),
            request.handledAt == nil, request.disposition == nil,
            let due = request.dueAt, due <= now else { return }
        request.disposition = "dismissed"
        request.handledAt = now
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// Opens the stored message without starting model work, and durably claims its chat.
    static func openFollowUp(
        id: UUID,
        context: ModelContext,
        legacySpaceID: UUID? = nil,
        now: Date = .now
    ) throws -> UUID {
        guard let request = try context.fetch(FetchDescriptor<AgentInitiativeRequest>())
            .first(where: { $0.id == id })
        else {
            throw InitiativeError.staleNotification
        }
        if let chatID = request.chatID {
            guard try context.fetch(FetchDescriptor<Chat>()).contains(where: { $0.id == chatID })
            else {
                throw InitiativeError.missingChat
            }
            return chatID
        }
        guard request.handledAt == nil, request.disposition == nil,
              request.dueAt == nil || request.dueAt! <= now
        else { throw InitiativeError.staleNotification }
        let spaceID = request.dueAt == nil ? legacySpaceID : request.spaceID
        guard try validScope(agentID: request.agentID, spaceID: spaceID, context: context) else {
            throw InitiativeError.staleNotification
        }
        let chat = Chat(agentID: request.agentID, spaceID: spaceID)
        if let title = request.title, !title.isEmpty {
            chat.title = title
            chat.titleOrigin = .edited
        }
        context.insert(chat)
        if let summary = request.summary, !summary.isEmpty {
            let briefing = Message(
                role: "system",
                content: "Summary of earlier conversation:\n\n\(summary)"
            )
            briefing.isCompactionSummary = true
            briefing.chat = chat
            context.insert(briefing)
        }
        let message = Message(role: "assistant", content: request.message)
        message.chat = chat
        context.insert(message)
        request.chatID = chat.id
        request.disposition = "opened"
        request.handledAt = now
        do { try context.save() } catch { context.rollback(); throw error }
        return chat.id
    }

    private static func preview(_ message: String) -> String {
        let plain = (try? AttributedString(markdown: message)).map { parsed in
            // Presentation runs preserve block boundaries that Markdown parsing removes.
            parsed.runs[\.presentationIntent].map { _, range in
                String(parsed[range].characters)
            }.joined(separator: " ")
        } ?? message
        let compact = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return compact.count > 200 ? String(compact.prefix(199)) + "…" : compact
    }
}
