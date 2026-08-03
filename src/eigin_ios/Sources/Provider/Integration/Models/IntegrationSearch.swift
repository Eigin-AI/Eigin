import Foundation

/// Text matching for the Add Integration search field.
enum IntegrationSearch {
    /// Integration types whose display name, description, or category name
    /// contains `query`, case-insensitively. An empty query matches nothing.
    static func matching(
        _ query: String,
        in types: [IntegrationType] = BundledIntegrationType.all
    ) -> [IntegrationType] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }
        return types.filter { type in
            type.displayName.lowercased().contains(normalized) ||
                type.description.lowercased().contains(normalized) ||
                type.category.displayName.lowercased().contains(normalized)
        }
    }
}
