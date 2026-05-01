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
    let defaultPermissionLevel: ToolPermissionLevel
    let category: Category

    // MARK: - Category

    /// Grouping for the permissions UI. Display metadata lives here since
    /// categories are a UI concept, not a per-tool concern.
    enum Category: String, CaseIterable {
        case agent
        case chats
        case system
        case external

        var displayName: String {
            switch self {
            case .agent: Localized.ToolCategory.agent
            case .chats: Localized.ToolCategory.chats
            case .system: Localized.ToolCategory.system
            case .external: Localized.ToolCategory.external
            }
        }

        var systemImage: String {
            switch self {
            case .agent: "person.crop.circle.fill"
            case .chats: "bubble.fill"
            case .system: "gearshape.fill"
            case .external: "globe"
            }
        }

        var color: Color {
            switch self {
            case .agent: .purple
            case .chats: .blue
            case .system: .green
            case .external: .orange
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
            defaultPermissionLevel = known.defaultPermissionLevel
            category = known.category
        } else {
            displayName = key
            defaultPermissionLevel = .ask
            category = .external
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(key, forKey: .key)
    }
}
