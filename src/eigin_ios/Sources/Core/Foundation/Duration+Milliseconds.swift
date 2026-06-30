import Foundation

extension Duration {
    /// This duration in whole milliseconds, truncated.
    ///
    /// Useful for logging elapsed time from `ContinuousClock` measurements.
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
