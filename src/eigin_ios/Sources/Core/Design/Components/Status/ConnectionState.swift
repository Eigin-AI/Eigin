import SwiftUI

/// One vocabulary for "is this thing working": the states a connection can be
/// in. Amber and red divide by who can act — `attention` is a job the person
/// can do, so screens carry a button for it; `unavailable` is an outage, so no
/// button ever appears beneath it.
enum ConnectionState {
    /// Up and usable.
    case connected
    /// In flight — the hollow dot in motion: work has nothing to report yet.
    case connecting
    /// Wants something from you — a key to replace, a sign-in to renew.
    case attention
    /// Down through no fault of yours; nothing to press.
    case unavailable
    /// Not in use — for a local model that is not installed, say.
    case off
    /// Turned off by choice.
    case disabled
}
