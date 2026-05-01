import Foundation

/// Converts ``OnboardingData`` into the agent's initial core texts.
///
/// These are starter texts — the agent refines them over time through regular use.
enum OnboardingAgentFactory {
    static func configure(agent: Agent, from data: OnboardingData) {
        agent.name = data.agentName ?? "Agent"
        agent.identityCore = buildIdentity(data)
        agent.userCore = buildUser(data)
        if agent.soulCore.isEmpty {
            agent.soulCore = AgentBootstrapPrompt.soulTemplate
        }
    }

    // MARK: - Private

    private static func buildIdentity(_ data: OnboardingData) -> String {
        var parts: [String] = []
        if let style = data.stylePreference {
            parts.append("A \(style.lowercased()) assistant.")
        }
        if let context = data.userContext {
            parts.append("Built around \(context.lowercased()).")
        }
        return parts.joined(separator: " ")
    }

    private static func buildUser(_ data: OnboardingData) -> String {
        var parts: [String] = []
        if let name = data.userName { parts.append("Name: \(name).") }
        if let about = data.userAbout { parts.append("Background: \(about).") }
        if let context = data.userContext { parts.append("Uses AI for: \(context).") }
        if let style = data.stylePreference { parts.append("Prefers \(style.lowercased()).") }
        if let priority = data.priority { parts.append("Priority: \(priority.rawValue).") }
        return parts.joined(separator: " ")
    }
}
