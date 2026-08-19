import Foundation

enum WebToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        WebSearchTool.capability,
        WebFetchTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        [
            WebSearchTool(),
            WebFetchTool(onBrowse: context.onBrowse),
        ]
    }
}
