import Foundation

enum SystemToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        GetTimeAndPlaceTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        [GetTimeAndPlaceTool(canPromptUser: context.canPromptUser)]
    }
}
