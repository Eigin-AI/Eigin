import Foundation
import SwiftData

/// Multiple `Agent` rows can exist (e.g. an accidental re-onboarding leaves the original
/// agent alongside a freshly created one). Exactly one is "the" agent until we formally
/// support retiring or switching agents — the oldest by `createdAt`, so an accidental
/// re-onboard never takes over from the agent the user has been building a relationship with.
extension Collection<Agent> {
    var primary: Agent? {
        self.min(by: { $0.createdAt < $1.createdAt })
    }
}

extension Agent {
    /// Fetches the same agent as `Collection.primary`, for call sites that need a
    /// `FetchDescriptor` rather than an in-memory `@Query` result.
    static var primaryDescriptor: FetchDescriptor<Agent> {
        FetchDescriptor<Agent>(sortBy: [SortDescriptor(\.createdAt)])
    }
}
