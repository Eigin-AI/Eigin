import Factory
import Foundation
import SwiftData

/// Presents skill connection requests through the current chat's confirmation gate.
@MainActor
struct SkillConnectionRequest {
    let chatID: UUID?
    let onConnectCapability: ConnectCapabilityHandler?
    let capabilityDeclines: DeclinedCapabilities
    let connectionGate: SkillConnectionGate?
    let userMessageID: String?

    // MARK: - Connecting what a skill needs

    /// Asks the person to connect what a skill needs, once. Returns `nil` when
    /// it is now connected, or what to tell the agent when it isn't. None of
    /// these are errors: a no is an answer, and the agent carries on without.
    func connect(
        _ missing: Set<Capability>,
        skillID: String,
        agent: Agent,
        context: ModelContext,
        toolCallID id: String
    ) async -> ToolResult? {
        let providers = SkillCatalog.providers(for: missing)
        // Within a capability any provider is enough ("or"); a skill needs
        // all of its capabilities ("and").
        let names = SkillCatalog.providerNames(for: missing)

        if missing.allSatisfy(capabilityDeclines.isDeclined) {
            return notConnected(
                "The user declined to connect \(names). Don't activate this skill again; if it would help, tell them they can add it in Settings → Connections.",
                toolCallID: id
            )
        }
        guard let onConnectCapability else {
            return notConnected(
                "Using this skill needs \(names) connected, and the user can't be asked right now. Answer without it; they can add it in Settings → Connections.",
                toolCallID: id
            )
        }
        if await isRefusedByIOS(providers) {
            return notConnected(
                "iOS has \(names) turned off for Eigin, so it can't be connected. Answer without it, and tell them they can allow Eigin in the iOS Settings app, then add it in this app's Settings → Connections.",
                toolCallID: id
            )
        }

        guard let chatID, let connectionGate else {
            return notConnected(
                Prompt.Skills.connectionUnavailable,
                toolCallID: id
            )
        }
        let attempt: UUID
        switch connectionGate.request(
            chatID: chatID,
            skillID: skillID,
            missing: missing,
            messageID: userMessageID
        ) {
        case .askUser, .waitForUser:
            return confirmationRequired(missing, names: names, toolCallID: id)
        case .connect(let reservation):
            attempt = reservation
        }
        defer { connectionGate.finish(chatID: chatID, skillID: skillID, attempt: attempt) }
        guard !Task.isCancelled else {
            return notConnected(
                Prompt.Skills.connectionCancelled(connections: names),
                toolCallID: id
            )
        }
        let request = CapabilityRequest(
            capabilities: missing,
            providerIDs: providers.map(\.id),
            agentName: agent.name
        )
        return await connectionOutcome(
            onConnectCapability(request), missing: missing, names: names,
            context: context, toolCallID: id
        )
    }

    @MainActor private func confirmationRequired(
        _ missing: Set<Capability>, names: String, toolCallID id: String
    ) -> ToolResult {
        ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "activated": false,
                "status": "confirmation_required",
                "capabilities": missing.map(\.rawValue).sorted(),
                "reason": Prompt.Skills.connectionConfirmation(connections: names),
            ]),
            isError: false
        )
    }

    @MainActor private func connectionOutcome(
        _ outcome: CapabilityConnectResult,
        missing: Set<Capability>, names: String,
        context: ModelContext, toolCallID id: String
    ) -> ToolResult? {
        switch outcome {
        case .connected:
            missing.forEach(capabilityDeclines.clear)
            // Verify every requested capability before activating.
            if let remaining = notConnectedAfterConnect(missing, context: context) {
                return notConnected(
                    Prompt.Skills.connectionIncomplete(connections: remaining),
                    toolCallID: id
                )
            }
            return nil
        case .declined:
            missing.forEach(capabilityDeclines.decline)
            return notConnected(
                "The user chose not to connect \(names). Don't activate this skill again; answer without it. If it would help later, they can add it in Settings → Connections.",
                toolCallID: id
            )
        case .cancelled:
            return notConnected(
                Prompt.Skills.connectionCancelled(connections: names),
                toolCallID: id
            )
        }
    }

    /// Capabilities from the request that no integration ended up
    /// connecting — the sheet lets the person stop after one of several.
    @MainActor private func notConnectedAfterConnect(
        _ missing: Set<Capability>,
        context: ModelContext
    ) -> String? {
        let integrations = ((try? context.fetch(FetchDescriptor<Integration>())) ?? [])
            .filter(\.isEnabled)
        let connected = Container.shared.integrationManager()
            .connectedCapabilities(integrations: integrations)
        let remaining = missing.subtracting(connected)
        guard !remaining.isEmpty else { return nil }
        return ListFormatter.localizedString(byJoining: remaining.map(\.displayName))
    }

    /// Whether iOS has already refused every provider, so there is nothing
    /// left to ask. Only platform integrations can be refused like this.
    @MainActor private func isRefusedByIOS(_ providers: [IntegrationType]) async -> Bool {
        for provider in providers {
            guard let source = provider.authKind.platform,
                  await source.permission().access() == .refused
            else { return false }
        }
        return !providers.isEmpty
    }

    @MainActor private func notConnected(_ reason: String, toolCallID id: String) -> ToolResult {
        ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: ["activated": false, "reason": reason]),
            isError: false
        )
    }
}
