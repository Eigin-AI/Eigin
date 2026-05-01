import Foundation

struct GetPresentationTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "get_presentation",
        displayName: Localized.Tools.Get.presentation,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "get_presentation"
    var isSmallContext: Bool = false
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .agent
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    nonisolated(unsafe) var voiceService: (any VoiceService)?

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Get your current display name, emoji, and voice.",
            parameters: JSONSchema(type: "object")
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        var voiceName = "System Default"
        if let voiceID = agent.voiceIdentifier, !voiceID.isEmpty {
            if let service = voiceService {
                let language = LanguageManager().currentLanguage
                let (recommended, other) = service.voices(for: language)
                voiceName = recommended.first(where: { $0.id == voiceID })?.name
                    ?? other.first(where: { $0.id == voiceID })?.name
                    ?? "Unknown"
            }
        }

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "name": agent.name,
                "emoji": agent.emoji,
                "voice": voiceName,
            ]),
            isError: false
        )
    }
}
