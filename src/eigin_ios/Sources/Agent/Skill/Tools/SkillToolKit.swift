import Foundation

enum SkillToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        ActivateSkillTool.capability,
        SearchSkillsTool.capability,
        StartFlowTool.capability,
        AdvanceFlowTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        [
            ActivateSkillTool(
                chatID: context.chatID,
                onConnectCapability: context.onConnectCapability
            ),
            SearchSkillsTool(chatID: context.chatID),
            StartFlowTool(chatID: context.chatID),
            AdvanceFlowTool(chatID: context.chatID),
        ]
    }
}
