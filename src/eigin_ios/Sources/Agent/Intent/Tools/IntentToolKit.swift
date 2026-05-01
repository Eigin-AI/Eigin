import Factory
import Foundation

enum IntentToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        SetIntentTool.capability,
        ListIntentsTool.capability,
        ResolveIntentTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        let intentService = Container.shared.intentService()

        return [
            SetIntentTool(
                intentService: intentService,
                spaceID: context.spaceID,
                chatID: context.chatID
            ),
            ListIntentsTool(
                intentService: intentService,
                accessPolicy: context.accessPolicy
            ),
            ResolveIntentTool(intentService: intentService),
        ]
    }
}
