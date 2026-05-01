import Foundation

enum IntentStatus: String, Codable {
    case active
    case resolved
    case dismissed
}

/// Developer-tunable decay constants for intent strength.
enum IntentDecay {
    static let baseHalfLifeDays = 3
    static let reinforcementBonusDays = 2
    static let maxHalfLifeDays = 14
    static let activeThreshold = 0.1
}
