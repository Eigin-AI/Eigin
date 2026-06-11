import Factory
import Foundation

enum HealthToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        SearchFoodTool.capability,
        GetFoodDetailsTool.capability,
        LogFoodTool.capability,
        LogBodyMeasurementTool.capability,
        LogSleepTool.capability,
        GetHealthLogTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        let healthService = Container.shared.healthService()

        return [
            SearchFoodTool(),
            GetFoodDetailsTool(),
            LogFoodTool(healthService: healthService, canPromptUser: context.canPromptUser),
            LogBodyMeasurementTool(
                healthService: healthService, canPromptUser: context.canPromptUser
            ),
            LogSleepTool(healthService: healthService, canPromptUser: context.canPromptUser),
            GetHealthLogTool(healthService: healthService, canPromptUser: context.canPromptUser),
        ]
    }
}
