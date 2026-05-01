import Foundation

enum SkillToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        ActivateSkillTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        [ActivateSkillTool(chatID: context.chatID)]
    }
}
