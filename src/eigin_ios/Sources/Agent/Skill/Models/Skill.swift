import Foundation

/// A packaged capability the agent can activate on demand.
///
/// Skills bundle instructions (injected into the system prompt when active)
/// with the tools they require. The active tool set is the union of all
/// active skills' ``requiredTools``.
struct Skill: Identifiable {
    let id: String
    let displayName: String
    let description: String
    let instruction: String
    /// Short instruction for small on-device models (~1-2 sentences).
    var smallInstruction: String = ""
    let requiredTools: Set<ToolCapability>
    let alwaysActive: Bool
}

// MARK: - Hashable (identity = id)

extension Skill: Hashable {
    static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
