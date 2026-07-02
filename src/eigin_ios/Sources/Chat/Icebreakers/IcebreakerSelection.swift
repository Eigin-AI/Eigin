import Foundation

/// Chooses and orders the icebreaker groups shown on an empty chat.
enum IcebreakerSelection {
    /// The default cap on how many groups to surface, to keep the blank slate focused.
    static let defaultLimit = 5

    /// Featured groups first, then by ascending `order`, breaking ties by `id` for
    /// stability. Capped at `limit` groups.
    static func groups(
        from all: [IcebreakerGroup] = IcebreakerRegistry.all,
        limit: Int = defaultLimit
    ) -> [IcebreakerGroup] {
        all
            .sorted { lhs, rhs in
                if lhs.featured != rhs.featured { return lhs.featured }
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.id < rhs.id
            }
            .prefix(limit)
            .map { $0 }
    }
}
