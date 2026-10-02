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
    /// Capabilities this skill needs from a connected integration (e.g. `.email`).
    /// Empty for skills that only use built-in tools.
    var requiredCapabilities: Set<Capability> = []
    let alwaysActive: Bool
    /// Authored, retrieval-optimized semantic description (English) — written to
    /// match the phrasing users actually use. `nil` falls back to ``description``.
    /// Latin-script model, so one English descriptor matches Danish queries too.
    var customDescriptor: String?

    /// The matching target for skill retrieval (hints + search).
    var descriptor: String {
        customDescriptor ?? description
    }

    /// One-line description for hint lists and search results — capped so
    /// verbose MCP instructions stay bounded in rendered context.
    var summaryLine: String {
        let limit = 160
        return smallInstruction.count > limit
            ? String(smallInstruction.prefix(limit)) + "…"
            : smallInstruction
    }
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
