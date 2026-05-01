import Factory
import Foundation

enum FoodToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        SearchFoodTool.capability,
        GetFoodDetailsTool.capability,
        LogFoodTool.capability,
        GetFoodLogTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        let healthService = Container.shared.healthService()

        return [
            SearchFoodTool(),
            GetFoodDetailsTool(),
            LogFoodTool(healthService: healthService, canPromptUser: context.canPromptUser),
            GetFoodLogTool(healthService: healthService, canPromptUser: context.canPromptUser),
        ]
    }
}
