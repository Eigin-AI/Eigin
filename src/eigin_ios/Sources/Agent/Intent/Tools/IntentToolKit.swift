import Factory
import Foundation

enum IntentToolKit: ToolKit {
    static let initiativeToolNames = [
        ListInitiativesTool.toolName, SetInitiativesTool.toolName, CancelInitiativeTool.toolName,
    ]

    static var capabilityAliases: [String: ToolCapability] {
        Dictionary(uniqueKeysWithValues: initiativeToolNames.map { (
            $0,
            SetInitiativesTool.capability
        ) })
    }

    static let capabilities: [ToolCapability] = [
        AddIntentTool.capability,
        UpdateIntentTool.capability,
        ListIntentsTool.capability,
        ResolveIntentTool.capability,
        SetInitiativesTool.capability,
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
                accessPolicy: context.accessPolicy,
                initiativeService: Container.shared.initiativeService()
            ),
            ResolveIntentTool(intentService: intentService),
            ListInitiativesTool(
                service: Container.shared.initiativeService(),
                spaceID: context.spaceID
            ),
            SetInitiativesTool(
                service: Container.shared.initiativeService(),
                spaceID: context.spaceID,
                canPromptUser: context.canPromptUser
            ),
            CancelInitiativeTool(
                service: Container.shared.initiativeService(),
                spaceID: context.spaceID
            ),
        ]
    }
}
