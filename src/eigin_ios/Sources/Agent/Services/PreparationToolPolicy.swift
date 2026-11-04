import Foundation

/// Preparation may read external context and save findings, never perform scheduled actions.
enum PreparationToolPolicy {
    static let allowedNames: Set<String> = [
        WebSearchTool.capability.key, WebFetchTool.capability.key,
        ListEmailsTool.capability.key, SearchEmailsTool.capability.key,
        ReadEmailTool.capability.key,
        GetCalendarEventsTool.capability.key, GetRemindersTool.capability.key,
        GetAulaUpdatesTool.capability.key, GetAulaChildrenTool.capability.key,
        GetAulaCalendarTool.capability.key, ListAulaMessagesTool.capability.key,
        ReadAulaMessageTool.capability.key,
        ListIntentsTool.capability.key, ListInitiativesTool.toolName,
        SearchKnowledgeTool.capability.key, GetKnowledgeTool.capability.key,
        SavePreparationTool.capability.key, SearchSkillsTool.capability.key,
        ActivateSkillTool.capability.key, ListChatsTool.capability.key,
        GetChatTranscriptTool.capability.key,
    ]

    static func allows(_ name: String) -> Bool {
        allowedNames.contains(name)
    }
}
