import Factory
import Foundation

enum KnowledgeToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        SearchKnowledgeTool.capability,
        SavePreparationTool.capability,
        GetKnowledgeTool.capability,
        AddKnowledgeTool.capability,
        UpdateKnowledgeTool.capability,
        DeleteKnowledgeTool.capability,
        ForgetKnowledgeTool.capability,
        SupersedeKnowledgeTool.capability,
        MergeKnowledgeTool.capability,
        ContestKnowledgeTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        tools(
            context: context,
            knowledgeService: Container.shared.knowledgeService(),
            exposesSourceChat: true
        )
    }

    /// Uses run-scoped knowledge and leaves chat retrieval to the transcript tools.
    @MainActor static func backgroundTools(
        context: ToolContext, knowledgeService: any KnowledgeService
    ) -> [any Tool] {
        tools(context: context, knowledgeService: knowledgeService, exposesSourceChat: false)
    }

    @MainActor private static func tools(
        context: ToolContext, knowledgeService: any KnowledgeService, exposesSourceChat: Bool
    ) -> [any Tool] {
        [
            SearchKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: context.spaceID,
                agentID: context.agentID
            ),
            GetKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: context.spaceID,
                agentID: context.agentID,
                exposesSourceChat: exposesSourceChat
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
            ForgetKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: context.spaceID,
                agentID: context.agentID
            ),
            SupersedeKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: context.spaceID,
                agentID: context.agentID,
                chatID: context.chatID
            ),
            MergeKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: context.spaceID,
                agentID: context.agentID,
                chatID: context.chatID
            ),
            ContestKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: context.spaceID,
                agentID: context.agentID
            ),
        ]
    }
}
