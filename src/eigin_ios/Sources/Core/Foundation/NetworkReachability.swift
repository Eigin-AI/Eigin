import Foundation
import Network
import os

/// Reports whether the device currently has a usable network path.
///
/// A satisfied path is necessary but not sufficient for reaching the internet: captive
/// portals and dead uplinks both report satisfied. Callers that need certainty should
/// treat this as a fast negative check (an unsatisfied path definitely cannot reach a
/// cloud provider) and confirm the positive case by actually making the request.
protocol NetworkReachability: Sendable {
    /// False only when the system reports no usable path at all, e.g. airplane mode.
    var isReachable: Bool { get }
}

/// ``NetworkReachability`` backed by `NWPathMonitor`.
///
/// Starts monitoring on init and runs for the process lifetime, so reads are a cheap
/// lock-guarded lookup of the last reported status rather than a live query.
final class DefaultNetworkReachability: NetworkReachability {
    private let monitor = NWPathMonitor()
    private let state = OSAllocatedUnfairLock(initialState: true)

    var isReachable: Bool {
        state.withLock { $0 }
    }

    init() {
        monitor.pathUpdateHandler = { [state] path in
            let reachable = path.status == .satisfied
            let changed = state.withLock { current -> Bool in
                guard current != reachable else { return false }
                current = reachable
                return true
            }
            guard changed else { return }
            AppLogger.info(
                "Network path is now \(public: reachable ? "reachable" : "unreachable")",
                category: .routing
            )
        }
        monitor.start(queue: DispatchQueue(label: "eigin.network-reachability"))
    }

    deinit {
        monitor.cancel()
    }
}
