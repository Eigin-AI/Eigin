import Foundation
import SwiftUI

/// Identifies each permissionable agent action.
///
/// Built-in tools define their own capability via `static let capability`.
/// MCP tools create discovered capabilities at runtime.
///
/// Identity (`Hashable`/`Codable`) uses only `kind` + `key`; metadata
/// (display name, default level, category) is carried for convenience
/// but excluded from equality and encoding.
struct ToolCapability {
    let kind: GrantKind
    let key: String
    let displayName: String
    let description: String?
    let defaultPermissionLevel: ToolPermissionLevel
    let category: Category
    /// Whether the user can grant or deny this in the permissions UI.
    /// `false` for agent machinery (done, background notify, skill flows) that
    /// has no meaningful user-facing permission decision — the app always allows it.
    let isUserConfigurable: Bool

    init(
        kind: GrantKind,
        key: String,
        displayName: String,
        description: String? = nil,
        defaultPermissionLevel: ToolPermissionLevel,
        category: Category,
        isUserConfigurable: Bool = true
    ) {
        self.kind = kind
        self.key = key
        self.displayName = displayName
        self.description = description
        self.defaultPermissionLevel = defaultPermissionLevel
        self.category = category
        self.isUserConfigurable = isUserConfigurable
    }

    // MARK: - Category

    /// Grouping for the permissions UI. Display metadata lives here since
    /// categories are a UI concept, not a per-tool concern.
    enum Category: String, CaseIterable {
        case agent
        case chats
        case knowledge
        case skills
        case web
        case email
        case familyAndSchool
        case timeAndPlace
        case calendar
        case reminders
        case health
        case extensions

        var displayName: String {
            switch self {
            case .agent: Localized.ToolCategory.agent
            case .chats: Localized.ToolCategory.chats
            case .knowledge: Localized.ToolCategory.knowledge
            case .skills: Localized.ToolCategory.skills
            case .web: Localized.ToolCategory.web
            case .email: Localized.ToolCategory.email
            case .familyAndSchool: Localized.ToolCategory.familyAndSchool
            case .timeAndPlace: Localized.ToolCategory.timeAndPlace
            case .calendar: Localized.ToolCategory.calendar
            case .reminders: Localized.ToolCategory.reminders
            case .health: Localized.ToolCategory.health
            case .extensions: Localized.ToolCategory.extensions
            }
        }

        var systemImage: String {
            switch self {
            case .agent: "person.crop.circle.fill"
            case .chats: "bubble.fill"
            case .knowledge: "brain.fill"
            case .skills: "star.fill"
            case .web: "globe"
            case .email: "envelope.fill"
            case .familyAndSchool: "figure.child"
            case .timeAndPlace: "clock.fill"
            case .calendar: "calendar"
            case .reminders: "checklist"
            case .health: "heart.fill"
            case .extensions: "puzzlepiece.fill"
            }
        }

        var color: Color {
            switch self {
            case .agent: .purple
            case .chats: .blue
            case .knowledge: .indigo
            case .skills: .yellow
            case .web: .orange
            case .email: .red
            case .familyAndSchool: .pink
            case .timeAndPlace: .mint
            case .calendar: .green
            case .reminders: .teal
            case .health: .pink
            case .extensions: .gray
            }
        }
    }
}

// MARK: - Hashable (identity = kind + key)

extension ToolCapability: Hashable {
    static func == (lhs: ToolCapability, rhs: ToolCapability) -> Bool {
        lhs.kind == rhs.kind && lhs.key == rhs.key
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(key)
    }
}

// MARK: - Codable (only kind + key; metadata restored from registry on decode)

extension ToolCapability: Codable {
    enum CodingKeys: String, CodingKey { case kind, key }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(GrantKind.self, forKey: .kind)
        key = try container.decode(String.self, forKey: .key)
        if let known = ToolRegistry.capability(forKey: key) {
            displayName = known.displayName
            description = known.description
            defaultPermissionLevel = known.defaultPermissionLevel
            category = known.category
            isUserConfigurable = known.isUserConfigurable
        } else {
            displayName = key
            description = nil
            defaultPermissionLevel = .ask
            category = .extensions
            isUserConfigurable = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(key, forKey: .key)
    }
}
