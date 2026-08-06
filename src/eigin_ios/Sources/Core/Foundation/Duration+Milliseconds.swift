import Foundation

extension Duration {
    /// This duration in whole milliseconds, truncated.
    ///
    /// Useful for logging elapsed time from `ContinuousClock` measurements.
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }

    /// This duration in fractional seconds, for rate calculations.
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
