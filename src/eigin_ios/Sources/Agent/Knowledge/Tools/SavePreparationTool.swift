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
            description: "Save a useful sourced finding for active intents immediately. Recheck sources before updating a finding with the same stable id. Findings are context for later foreground work, not completed tasks. Only link intents in the same space.",
            parameters: JSONSchema(type: "object", properties: [
                "id": .init(
                    type: "string",
                    description: "Stable snake_case finding ID: 1–100 lowercase letters, digits or underscores, starting with a letter."
                ),
                "intent_ids": .init(
                    type: "array",
                    description: "1–10 related active intent UUIDs.",
                    items: .init(type: "string")
                ),
                "content": .init(
                    type: "string",
                    description: "Useful factual context, at most 6000 characters."
                ),
                "sources": .init(
                    type: "array",
                    description: "1–20 nonempty source URLs or provider item identifiers, each at most 2000 characters.",
                    items: .init(type: "string")
                ),
            ], required: ["id", "intent_ids", "content", "sources"])
        )
    }

    @MainActor func execute(_ call: ToolCall, agent: Agent) async -> ToolResult {
        do {
            guard let args = ToolHelpers.parseArguments(call.function.arguments) else {
                throw PreparationValidationError(
                    message: "Provide save_preparation arguments as a JSON object."
                )
            }
            guard let id = args["id"] as? String,
                  id.range(of: "^[a-z][a-z0-9_]{0,99}$", options: .regularExpression) != nil
            else {
                throw PreparationValidationError(
                    message: "id must be 1–100 lowercase letters, digits or underscores, starting with a letter."
                )
            }
            guard let texts = args["intent_ids"] as? [String], !texts.isEmpty, texts.count <= 10,
                  texts.allSatisfy({ UUID(uuidString: $0) != nil })
            else {
                throw PreparationValidationError(
                    message: "intent_ids must contain 1–10 valid intent UUIDs."
                )
            }
            guard let content = args["content"] as? String, !content.isEmpty, content.count <= 6000
            else {
                throw PreparationValidationError(
                    message: "content must be a nonempty string of at most 6000 characters."
                )
            }
            guard let sources = args["sources"] as? [String], !sources.isEmpty, sources.count <= 20,
                  sources.allSatisfy({ !$0.isEmpty && $0.count <= 2000 })
            else {
                throw PreparationValidationError(
                    message: "sources must contain 1–20 nonempty source URLs or provider item identifiers, each at most 2000 characters."
                )
            }
            let ids = texts.compactMap(UUID.init(uuidString:))
            let context = ModelContext(modelContainer)
            let intents = try context.fetch(FetchDescriptor<Intent>())
                .filter { ids.contains($0.id) }
            guard intents.count == Set(ids).count, let first = intents.first,
                  intents
                  .allSatisfy({
                      $0.agentID == agent.id && $0.intentStatus == .active && $0.spaceID == first
                          .spaceID && accessPolicy.canAccess(itemSpaceID: $0.spaceID) })
            else {
                throw PreparationValidationError(
                    message: "intent_ids must refer to accessible active intents belonging to this agent in the same space."
                )
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
                    FirmField(
                        name: "observed_at",
                        value: .dateTime(value: Date.now.ISO8601Format())
                    ),
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

/// Reports which preparation argument needs correction.
private struct PreparationValidationError: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}
