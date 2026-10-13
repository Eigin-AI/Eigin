import Foundation
import UIKit

/// What iOS lets Eigin do with a platform integration, as far as iOS will say.
enum PlatformAccess: Equatable, Sendable {
    /// iOS hasn't asked yet.
    case notAsked
    /// Allowed, apart from the kinds iOS has turned off.
    case allowed(notAllowed: Set<PlatformDataKind>)
    /// iOS refused and won't ask again: only Settings can change it.
    case refused
}

/// One kind of data a platform integration reads or saves, named as the
/// person would name it.
struct PlatformDataKind: Hashable, Sendable, Identifiable {
    enum Use: String, Sendable {
        case reads
        case saves
    }

    let use: Use
    /// Stable within one integration, e.g. `meals`.
    let key: String
    let name: String

    var id: String {
        "\(use.rawValue).\(key)"
    }

    /// Kinds as one phrase: "Activity, sleep and nutrition".
    static func listed(_ kinds: [PlatformDataKind]) -> String {
        let names = kinds.enumerated().map { index, kind in
            index == 0 ? kind.name : kind.name.lowercased()
        }
        return ListFormatter.localizedString(byJoining: names)
    }
}

/// The iOS permission behind a platform integration.
@MainActor
protocol PlatformPermission {
    /// What iOS allows now, without asking.
    func access() async -> PlatformAccess
    /// Asks iOS if it hasn't asked yet, then reports what it allows.
    func request() async -> PlatformAccess
}

/// What a platform integration is made of: the data it touches, who shows
/// the permission prompt, and the permission itself.
struct PlatformAccessSource: Sendable {
    let reads: [PlatformDataKind]
    let saves: [PlatformDataKind]
    /// Who shows the permission prompt: "iOS", or Apple Health, which asks
    /// for itself.
    let asker: String
    /// Built lazily, like an OAuth config, so services resolve at use.
    let permission: @MainActor @Sendable () -> any PlatformPermission
}
