import Factory
import Foundation

enum IntentToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        AddIntentTool.capability,
        UpdateIntentTool.capability,
        ListIntentsTool.capability,
        ResolveIntentTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        let intentService = Container.shared.intentService()

        return [
            AddIntentTool(
                intentService: intentService,
                spaceID: context.spaceID,
                chatID: context.chatID
            ),
            UpdateIntentTool(intentService: intentService),
            ListIntentsTool(
                intentService: intentService,
                accessPolicy: context.accessPolicy
            ),
            ResolveIntentTool(intentService: intentService),
        ]
    }
}
