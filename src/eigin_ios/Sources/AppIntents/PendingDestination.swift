import Foundation

/// The single pending-navigation store: a signal set outside the view tree
/// telling `ChatListView` what to open when it is next alive.
///
/// One UserDefaults key, last write wins — racing signals (a notification tap
/// plus a widget tap) resolve to a single navigation instead of stacking.
/// Written as a tagged string rather than raw JSON so intent code and the
/// handoff URL share one trivial codec with no other dependencies.
enum PendingDestination: Equatable {
    /// A background-agent notification was tapped; open the chat for that
    /// initiative request (formerly `PendingInitiative`).
    case initiative(UUID)
    /// A widget or app-shortcut tap; open a fresh chat in the route's mode.
    case newChat(EiginRoute)
    /// The onboarding conversation just became a real chat; open it once on
    /// first load (formerly `pendingOnboardingChat`).
    case chat(UUID)

    static let storageKey = "pendingDestination"

    static func set(_ destination: Self) {
        UserDefaults.standard.set(destination.taggedValue, forKey: storageKey)
    }

    static func get() -> Self? {
        guard let raw = UserDefaults.standard.string(forKey: storageKey) else { return nil }
        return Self(taggedValue: raw)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

private extension PendingDestination {
    init?(taggedValue: String) {
        let parts = taggedValue.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "initiative":
            guard let id = UUID(uuidString: String(parts[1])) else { return nil }
            self = .initiative(id)
        case "chat":
            guard let id = UUID(uuidString: String(parts[1])) else { return nil }
            self = .chat(id)
        case "route":
            guard let route = EiginRoute(rawValue: String(parts[1])) else { return nil }
            self = .newChat(route)
        default:
            return nil
        }
    }

    var taggedValue: String {
        switch self {
        case .initiative(let id): "initiative:\(id.uuidString)"
        case .chat(let id): "chat:\(id.uuidString)"
        case .newChat(let route): "route:\(route.rawValue)"
        }
    }
}
