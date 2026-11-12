import Foundation
import SwiftData

extension SkillConnectionRequest {
    /// Requests explicit setup approval for a bundled MCP preset through the chat gate.
    func connect(
        preset: MCPPreset, agent: Agent, context: ModelContext, toolCallID: String
    ) async -> ToolResult? {
        func inactive(_ reason: String, status: String = "not_connected") -> ToolResult {
            ToolResult(
                toolCallID: toolCallID,
                content: ToolHelpers.output(result: [
                    "activated": false, "status": status, "reason": reason,
                ]), isError: false
            )
        }
        guard !capabilityDeclines.isPresetDeclined(preset.id) else {
            return inactive(
                Prompt.Skills.presetDeclined(connection: preset.displayName)
            )
        }
        guard let onConnectCapability, let chatID, let connectionGate else {
            return inactive(Prompt.Skills.connectionUnavailable)
        }
        let attempt: UUID
        switch connectionGate.request(
            chatID: chatID, skillID: preset.skillID, target: .mcpPreset(preset.id),
            messageID: userMessageID
        ) {
        case .askUser, .waitForUser:
            return inactive(
                Prompt.Skills.connectionConfirmation(connections: preset.displayName),
                status: "confirmation_required"
            )
        case .connect(let reservation):
            attempt = reservation
        }
        defer { connectionGate.finish(chatID: chatID, skillID: preset.skillID, attempt: attempt) }
        guard !Task.isCancelled else {
            return inactive(Prompt.Skills.connectionCancelled(connections: preset.displayName))
        }
        let outcome = await onConnectCapability(CapabilityRequest(
            capabilities: [], providerIDs: [], agentName: agent.name, presetID: preset.id
        ))
        guard !Task.isCancelled else {
            return inactive(Prompt.Skills.connectionCancelled(connections: preset.displayName))
        }
        switch outcome {
        case .connected:
            let servers = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
            guard preset.server(in: servers)?.isEnabled == true else {
                return inactive(Prompt.Skills.connectionIncomplete(connections: preset.displayName))
            }
            capabilityDeclines.clearPreset(preset.id)
            return nil
        case .declined:
            capabilityDeclines.declinePreset(preset.id)
            return inactive(
                Prompt.Skills.presetDeclined(connection: preset.displayName)
            )
        case .cancelled:
            return inactive(Prompt.Skills.connectionCancelled(connections: preset.displayName))
        case .failed(let reason):
            return inactive(
                Prompt.Skills.connectionFailed(connections: preset.displayName, reason: reason),
                status: "connection_failed"
            )
        }
    }
}
