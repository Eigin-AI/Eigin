import Foundation

enum SystemToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        GetTimeAndPlaceTool.capability,
        SearchPlacesTool.capability,
        GetDirectionsTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        [
            GetTimeAndPlaceTool(canPromptUser: context.canPromptUser),
            SearchPlacesTool(),
            GetDirectionsTool(),
        ]
    }
}
