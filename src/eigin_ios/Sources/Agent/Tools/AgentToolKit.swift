import Factory
import Foundation

enum AgentToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        ReadCoreTool.capability,
        EditCoreTool.capability,
        GetPresentationTool.capability,
        SetPresentationTool.capability,
        SetProactivityTool.capability,
        ManageVocabularyTool.capability,
        PresentOptionsTool.capability,
        FollowUpTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        let voiceService = Container.shared.voiceService()
        let dictationService = Container.shared.dictationService()
        let knowledgeService = Container.shared.knowledgeService()
        let vocabularyStore = Container.shared.vocabularyStore()

        return [
            FollowUpTool(
                scheduler: Container.shared.followUpScheduler(),
                canPromptUser: context.canPromptUser
            ),
            ReadCoreTool(),
            EditCoreTool(),
            GetPresentationTool(voiceService: voiceService),
            SetPresentationTool(
                voiceService: voiceService,
                voiceNames: context.voiceNames,
                knowledgeService: knowledgeService,
                agentID: context.agentID
            ),
            SetProactivityTool(),
            ManageVocabularyTool(
                vocabularyStore: vocabularyStore,
                dictationService: dictationService
            ),
            PresentOptionsTool(onPresentOptions: context.onPresentOptions),
        ]
    }
}
