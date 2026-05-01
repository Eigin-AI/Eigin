import Foundation

enum MCPAuthType: String, Codable {
    case none
    case oauth

    var displayName: String {
        switch self {
        case .none: "Open"
        case .oauth: "OAuth"
        }
    }
}
