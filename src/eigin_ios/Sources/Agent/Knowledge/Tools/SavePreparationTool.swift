import Foundation
import SwiftData

/// Saves sourced findings in the linked intents' exact scope as soon as they are discovered.
struct SavePreparationTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "save_preparation", displayName: Localized.Tools.Agent.savePreparation,
        description: Localized.Tools.Description.savePreparation,
        defaultPermissionLevel: .always, category: .knowledge
    )
    let name = "save_preparation"
    let modelContainer: ModelContainer
    let knowledgeService: any KnowledgeService
    let accessPolicy: SpaceAccessPolicy
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .knowledge
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Save a useful sourced finding for active intents immediately. Use the same stable id to update the same finding. observed_at is when you checked the source, not when you edit the note. Findings are context for later foreground work, not completed tasks. Only link intents in the same space.",
            parameters: JSONSchema(type: "object", properties: [
                "id": .init(type: "string", description: "Stable snake_case finding ID."),
                "intent_ids": .init(
                    type: "array",
                    description: "Related active intent UUIDs.",
                    items: .init(type: "string")
                ),
                "content": .init(
                    type: "string",
                    description: "Useful factual context, at most 6000 characters."
                ),
                "sources": .init(
                    type: "array",
                    description: "Source URLs or provider item identifiers.",
                    items: .init(type: "string")
                ),
                "observed_at": .init(
                    type: "string",
                    description: "ISO8601 time when the sources were checked."
                ),
            ], required: ["id", "intent_ids", "content", "sources", "observed_at"])
        )
    }

    @MainActor func execute(_ call: ToolCall, agent: Agent) async -> ToolResult {
        do {
            guard let args = ToolHelpers.parseArguments(call.function.arguments),
                  let id = args["id"] as? String, id.range(
                      of: "^[a-z][a-z0-9_]{0,99}$",
                      options: .regularExpression
                  ) != nil,
                  let texts = args["intent_ids"] as? [String], !texts.isEmpty, texts.count <= 10,
                  let content = args["content"] as? String, !content.isEmpty, content.count <= 6000,
                  let sources = args["sources"] as? [String], !sources.isEmpty, sources.count <= 20,
                  sources.allSatisfy({ !$0.isEmpty && $0.count <= 2000 }),
                  let observed = args["observed_at"] as? String,
                  let date = ISO8601DateFormatter().date(from: observed),
                  date <= Date.now.addingTimeInterval(60)
            else {
                throw InitiativeError.invalidContent
            }
            let ids = texts.compactMap(UUID.init(uuidString:))
            guard ids.count == texts.count else { throw InitiativeError.inaccessibleIntent }
            let context = ModelContext(modelContainer)
            let intents = try context.fetch(FetchDescriptor<Intent>())
                .filter { ids.contains($0.id) }
            guard intents.count == Set(ids).count, let first = intents.first,
                  intents
                  .allSatisfy({
                      $0.agentID == agent.id && $0.intentStatus == .active && $0.spaceID == first
                          .spaceID && accessPolicy.canAccess(itemSpaceID: $0.spaceID) })
            else {
                throw InitiativeError.inaccessibleIntent
            }
            let scopedID = "\(agent.id.uuidString)_\(first.spaceID?.uuidString ?? "global")_\(id)"
                .lowercased().replacingOccurrences(
                    of: "-",
                    with: "_"
                )
            let entity = FirmEntity(
                id: "preparation.p_\(scopedID)",
                entityType: "preparation",
                fields: [
                    FirmField(name: "content", value: .string(value: content)),
                    FirmField(
                        name: "intent_ids",
                        value: .list(items: texts.map { .string(value: $0) })
                    ),
                    FirmField(
                        name: "sources",
                        value: .list(items: sources.map { .string(value: $0) })
                    ),
                    FirmField(name: "observed_at", value: .dateTime(value: date.ISO8601Format())),
                ]
            )
            try await knowledgeService.addEntity(
                entity,
                spaceID: first.spaceID,
                agentID: agent.id,
                chatID: nil
            )
            return ToolResult(
                toolCallID: call.id,
                content: ToolHelpers.output(result: ["saved": entity.id]),
                isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: call.id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
