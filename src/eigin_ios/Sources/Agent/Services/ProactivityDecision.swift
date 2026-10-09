import Foundation

/// Tracks whether the user has consciously chosen a proactivity level.
///
/// The choice is application-wide — there is one active agent. Once decided
/// (any level, including staying reactive) the agent stops offering.
enum ProactivityDecision {
    /// Injectable for tests; defaults to the standard store.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    /// Whether the user has made an explicit proactivity choice.
    static func isDecided() -> Bool {
        defaults.bool(forKey: key)
    }

    /// Records that the user made an explicit proactivity choice.
    static func markDecided() {
        defaults.set(true, forKey: key)
    }

    /// Clears the decision record — for tests.
    static func removeDecision() {
        defaults.removeObject(forKey: key)
    }

    private static let key = "proactivityDecided"
}
