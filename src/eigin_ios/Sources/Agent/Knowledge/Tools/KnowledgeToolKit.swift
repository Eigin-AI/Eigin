import Factory
import Foundation

enum KnowledgeToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        SearchKnowledgeTool.capability,
        GetKnowledgeTool.capability,
        AddKnowledgeTool.capability,
        UpdateKnowledgeTool.capability,
        DeleteKnowledgeTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        let knowledgeService = Container.shared.knowledgeService()

        return [
            SearchKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: context.spaceID,
                agentID: context.agentID
            ),
            GetKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: context.spaceID,
                agentID: context.agentID
            ),
            AddKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: context.spaceID,
                agentID: context.agentID,
                chatID: context.chatID
            ),
            UpdateKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: context.spaceID,
                agentID: context.agentID,
                chatID: context.chatID
            ),
            DeleteKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: context.spaceID,
                agentID: context.agentID
            ),
        ]
    }
}
