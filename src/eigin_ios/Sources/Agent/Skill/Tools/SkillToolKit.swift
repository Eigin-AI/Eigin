import Foundation

enum SkillToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        ActivateSkillTool.capability,
        StartFlowTool.capability,
        AdvanceFlowTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        [
            ActivateSkillTool(chatID: context.chatID),
            StartFlowTool(chatID: context.chatID),
            AdvanceFlowTool(chatID: context.chatID),
        ]
    }
}
