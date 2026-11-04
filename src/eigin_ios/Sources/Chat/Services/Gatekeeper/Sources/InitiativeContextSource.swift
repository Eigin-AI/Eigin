import Factory
import Foundation
import SwiftData

/// Supplies task instructions, occurrence outputs, and sourced preparation in initiative chats.
@MainActor final class InitiativeContextSource: SystemHintSource {
    let title = "Scheduled initiative"
    private let knowledgeService: any KnowledgeService
    private let modelContainer: ModelContainer

    init(
        knowledgeService: any KnowledgeService,
        modelContainer: ModelContainer = Container.shared.modelContainer()
    ) {
        self.knowledgeService = knowledgeService
        self.modelContainer = modelContainer
    }

    func render(_ input: SystemHintInput) async -> String? {
        guard let chatID = input.chatID else { return nil }
        let context = ModelContext(modelContainer)
        guard let occurrences = try? context.fetch(FetchDescriptor<InitiativeOccurrence>()),
              let occurrence = occurrences.first(where: { $0.chatID == chatID }),
              let registration = try? context.fetch(FetchDescriptor<InitiativeRegistration>())
              .first(where: { $0.id == occurrence.registrationID }),
              let delivery = try? JSONDecoder().decode(
                  InitiativeDelivery.self,
                  from: registration.payload
              ),
              delivery.agentID == input.agentID,
              delivery.spaceID == input.spaceID else { return nil }
        let initialTask = occurrence.completedAt == nil && !input.messages
            .contains(where: { $0.role == "user" })
        if initialTask, (try? InitiativeConversationService.validatedDelivery(
            registrationID: occurrence.registrationID,
            context: context
        )) == nil {
            return Prompt.Hints.Initiative.stale
        }
        let intentIDs = Set(occurrence.intentIDs)
        let outputs = history(
            occurrence: occurrence,
            occurrences: occurrences,
            input: input,
            context: context
        )
        var findingsText: [String] = []
        if let findings = try? await knowledgeService.unexpiredEntities(
            type: "preparation",
            spaceID: input.spaceID,
            agentID: input.agentID
        ) {
            let relevant = findings.filter { finding in
                guard case .list(let values) = finding.fields
                    .first(where: { $0.name == "intent_ids" })?.value else { return false }
                return values.contains { value in
                    guard case .string(let text) = value,
                          let id = UUID(uuidString: text) else { return false }
                    return intentIDs.contains(id)
                }
            }.sorted { observedAt($0) > observedAt($1) }
            for finding in relevant.prefix(input.isSmallContext ? 2 : 5) {
                let observed = observedAt(finding)
                let sources = finding.fields.first { $0.name == "sources" }
                    .map { String(describing: $0.value) } ?? "unknown"
                let content = finding.fields.first { $0.name == "content" }
                    .map { String(describing: $0.value) } ?? ""
                findingsText.append(Prompt.Hints.Initiative.finding(
                    entryID: finding.id,
                    observedAt: observed == .distantPast ? "unknown" : observed.ISO8601Format(),
                    sources: String(sources.prefix(600)), content: String(content.prefix(1000))
                ))
            }
        }
        return Prompt.Hints.Initiative.main(
            policy: initialTask ? Prompt.Hints.Initiative.current : Prompt.Hints.Initiative
                .historical,
            tasks: delivery.members.map { Prompt.Hints.Initiative.task(
                intentID: $0.intentID.uuidString,
                instructions: $0.instructions
            ) }.joined(separator: "\n"),
            outputs: outputs, findings: findingsText.joined(separator: "\n\n")
        )
    }

    private func history(
        occurrence: InitiativeOccurrence, occurrences: [InitiativeOccurrence],
        input: SystemHintInput, context: ModelContext
    ) -> String {
        let chats = (try? context.fetch(FetchDescriptor<Chat>())) ?? []
        let candidates = occurrences.compactMap { previous -> (InitiativeOccurrence, [Message])? in
            guard previous.chatID != occurrence.chatID,
                  (previous.startedAt ?? .distantPast) < (occurrence.startedAt ?? .now),
                  let chat = chats.first(where: { $0.id == previous.chatID }),
                  chat.agentID == input.agentID, chat.spaceID == input.spaceID else { return nil }
            let ids = Set(previous.outputMessageIDs)
            let messages = chat.messages
                .filter {
                    ids.contains($0.id) && $0.role == "assistant" && !$0.isCompactionSummary && !$0
                        .content.isEmpty
                }
                .sorted { $0.timestamp < $1.timestamp }
            return messages.isEmpty ? nil : (previous, messages)
        }.sorted { ($0.1.last?.timestamp ?? .distantPast) > ($1.1.last?.timestamp ?? .distantPast) }
        let perIntent = Set(occurrence.intentIDs).sorted { $0.uuidString < $1.uuidString }
            .map { id in
                Array(candidates.filter { $0.0.intentIDs.contains(id) }.prefix(3))
            }
        var selected: [(InitiativeOccurrence, [Message])] = []
        var seen = Set<String>()
        for index in 0 ..< 3 {
            for history in perIntent where index < history.count {
                let entry = history[index]
                if seen.insert(entry.0.id).inserted { selected.append(entry) }
            }
        }
        var remaining = input.isSmallContext ? 2500 : 7000
        let allowance = remaining / max(1, min(selected.count, 20))
        var sections: [String] = []
        for (previous, messages) in selected {
            let state = previous.completedAt == nil ? "partial" : "completed"
            let header = Prompt.Hints.Initiative.output(
                state: state,
                chatID: previous.chatID.uuidString,
                excerpt: ""
            )
            let budget = min(2400, allowance, remaining) - header.count - 2
            guard budget > 0 else { continue }
            let text = messages.map { "\($0.timestamp.ISO8601Format()): \($0.content)" }
                .joined(separator: "\n")
            let section = Prompt.Hints.Initiative.output(
                state: state,
                chatID: previous.chatID.uuidString,
                excerpt: String(text.suffix(budget))
            )
            sections.append(section)
            remaining -= section.count + 2
        }
        return sections.joined(separator: "\n\n")
    }

    private func observedAt(_ entity: FirmEntity) -> Date {
        guard let field = entity.fields.first(where: { $0.name == "observed_at" })
        else { return .distantPast }
        switch field.value {
        case .dateTime(let value),
             .string(let value): return ISO8601DateFormatter().date(from: value) ?? .distantPast
        default: return .distantPast
        }
    }
}
