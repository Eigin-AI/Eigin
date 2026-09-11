#if DEBUG || EIGIN_DEV
import Foundation
import os

/// A ``NetworkReachability`` whose answer the test sets.
final class FakeNetworkReachability: NetworkReachability, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<Bool>

    init(isReachable: Bool = true) {
        state = OSAllocatedUnfairLock(initialState: isReachable)
    }

    var isReachable: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}
#endif
