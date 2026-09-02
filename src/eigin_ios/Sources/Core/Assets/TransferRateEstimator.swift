import Foundation

/// Estimates seconds-left for a byte transfer without ever showing a wild
/// guess in the first seconds.
///
/// Byte deltas are pooled into sized windows (default 5 s) — never per-poll
/// rates, which are noisy during cold start, TLS setup, and throttle spikes.
/// The estimate stays `nil` until one full window has elapsed **and** a small
/// fraction of the asset has arrived, then tracks the exponential moving
/// average of window rates.
struct TransferRateEstimator {
    private var windowSeconds: Double
    /// Fraction of the asset that must arrive before an estimate is shown.
    private var baselineFraction: Double
    private var emaAlpha: Double

    /// Completed window count. One at minimum before estimating.
    private var windowsCompleted = 0
    private var windowBytes: Int64 = 0
    private var windowStart: ContinuousClock.Instant?
    /// EMA of window rates, bytes per second.
    private var emaRate: Double?
    private var lastCompletedBytes: Int64 = 0
    /// Whether the first tick after (re)start has been consumed. That tick
    /// can carry all bytes completed before a resume, so it must not count
    /// toward any window's rate.
    private var seeded = false

    init(
        windowSeconds: Double = 5,
        baselineFraction: Double = 0.05,
        emaAlpha: Double = 0.4
    ) {
        self.windowSeconds = windowSeconds
        self.baselineFraction = baselineFraction
        self.emaAlpha = emaAlpha
    }

    /// Feed the latest byte counts. Returns estimated seconds left, or nil
    /// while the baseline hasn't been established or the rate isn't usable.
    mutating func estimate(completedBytes: Int64, totalBytes: Int64, now: ContinuousClock.Instant)
        -> Double?
    {
        let delta = completedBytes - lastCompletedBytes
        if completedBytes < lastCompletedBytes {
            // Transfer restarted (or reset) — rebuild the baseline.
            reset()
        }
        lastCompletedBytes = completedBytes

        guard completedBytes > 0, totalBytes > 0 else { return nil }

        if !seeded {
            // Consume the first tick without earning bytes: on a resumed
            // transfer its delta includes everything from before the restart.
            seeded = true
            if windowStart == nil {
                windowStart = now
            }
            return nil
        }

        if windowStart == nil {
            windowStart = now
            windowBytes = 0
        }
        windowBytes += max(0, delta)

        // Close the window once it has run long enough.
        let elapsed = windowStart.map { $0.duration(to: now).secondsExact } ?? 0
        if elapsed >= windowSeconds {
            closeWindow(elapsedSeconds: elapsed)
            windowStart = now
            windowBytes = 0
        }

        guard windowsCompleted >= 1,
              let rate = emaRate, rate > 0
        else { return nil }

        let fraction = Double(completedBytes) / Double(totalBytes)
        guard fraction >= baselineFraction else { return nil }

        return Double(totalBytes - completedBytes) / rate
    }

    mutating func reset() {
        windowsCompleted = 0
        windowBytes = 0
        windowStart = nil
        emaRate = nil
        lastCompletedBytes = 0
        seeded = false
    }

    private mutating func closeWindow(elapsedSeconds: Double) {
        guard elapsedSeconds > 0 else { return }
        let rate = Double(windowBytes) / elapsedSeconds
        if let existing = emaRate {
            emaRate = emaAlpha * rate + (1 - emaAlpha) * existing
        } else {
            emaRate = rate
        }
        windowsCompleted += 1
    }
}

private extension Duration {
    var secondsExact: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
