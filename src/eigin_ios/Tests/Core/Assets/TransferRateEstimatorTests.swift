@testable import Eigin
import Foundation
import Testing

/// Verifies the cold-start behavior of ``TransferRateEstimator``: no guesses
/// before a stable baseline exists, stable EMA afterwards.
struct TransferRateEstimatorTests {
    private let total: Int64 = 1_000_000

    /// 100 KB/s constant feed. 5 s windows, baseline 5% of 1 MB = 50 KB.
    private func makeEstimator() -> TransferRateEstimator {
        TransferRateEstimator(windowSeconds: 5, baselineFraction: 0.05, emaAlpha: 1.0)
    }

    @Test func estimateIsNilBeforeFirstWindowCompletes() {
        var estimator = makeEstimator()
        var t: Double = 0
        var bytes: Int64 = 0

        // Feed 4 s at 100 KB/s — window not yet closed.
        while t < 4 {
            bytes += 100_000 / 10
            t += 0.5
            let estimate = estimator.estimate(
                completedBytes: bytes, totalBytes: total, now: now(t)
            )
            #expect(estimate == nil)
        }
    }

    @Test func estimateArrivesAfterBaselineWindow() {
        var estimator = makeEstimator()
        var bytes: Int64 = 0

        // 6 s at 100 KB/s: one full window closed and 600 KB > 5% transferred.
        for tick in 1 ... 12 {
            bytes += 50000
            _ = estimator.estimate(
                completedBytes: bytes, totalBytes: total, now: now(Double(tick) * 0.5)
            )
        }
        // Final tick lands at t = 6.5, one second after the window closed
        // at t = 5.5, so the estimate comes from that closed window.
        bytes += 50000
        let estimate = estimator.estimate(completedBytes: bytes, totalBytes: total, now: now(6.5))
        #expect(estimate != nil)
        if let estimate {
            // ~400 KB left at 100 KB/s → ~4 s. Allow sloppy bounds.
            #expect(estimate > 2 && estimate < 6)
        }
    }

    @Test func tinyFractionStillHidesEstimate() {
        var estimator = makeEstimator()
        var bytes: Int64 = 0
        // One full window closed, but only 1% transferred (< 5% baseline).
        for tick in 1 ... 10 {
            bytes += 1000
            _ = estimator.estimate(
                completedBytes: bytes, totalBytes: total, now: now(Double(tick) * 0.5)
            )
        }
        bytes += 1000
        let estimate = estimator.estimate(completedBytes: bytes, totalBytes: total, now: now(5.5))
        #expect(estimate == nil)
    }

    @Test func restartRebuildsBaseline() {
        var estimator = makeEstimator()
        // Prime the estimator past its baseline.
        var bytes = 200_000
        for tick in 1 ... 12 {
            _ = estimator.estimate(
                completedBytes: Int64(bytes), totalBytes: total, now: now(Double(tick) * 0.5)
            )
            bytes += 50000
        }
        // Transfer restarts from zero: the reset must hide the estimate again.
        let estimate = estimator.estimate(completedBytes: 10000, totalBytes: total, now: now(7.0))
        #expect(estimate == nil)
    }

    @Test func estimateTracksRateChanges() {
        var estimator = TransferRateEstimator(
            windowSeconds: 1, baselineFraction: 0.01, emaAlpha: 1.0
        )
        var bytes: Int64 = 0
        var t = 0.0

        // Half-second feeds at 100 KB/s; windows close at t = 1.5, 2.5, 3.5.
        for tick in 1 ... 7 {
            bytes += 50000
            t += 0.5
            _ = estimator.estimate(completedBytes: bytes, totalBytes: total, now: now(t))
        }
        // A fresh window carrying only the doubled rate: 200 KB in 1 s.
        bytes += 200_000
        t += 1.0
        let estimate = estimator.estimate(completedBytes: bytes, totalBytes: total, now: now(t))
        // Remaining: 450 KB at the new 200 KB/s rate → 2.25 s.
        #expect(estimate != nil)
        if let estimate {
            #expect(estimate > 2.1 && estimate < 2.4, "estimate was \(estimate)")
        }
    }

    @Test func rebootSeedsResumeBytesWithoutEarningRate() {
        var estimator = makeEstimator()

        // First tick carries 300 KB already on disk from a previous attempt.
        // It must not inflate the first window's rate.
        _ = estimator.estimate(completedBytes: 300_000, totalBytes: total, now: now(0.5))

        // Then a steady 100 KB/s feed: 10 ticks x 50 KB over 5 s.
        var bytes: Int64 = 300_000
        for tick in 1 ... 10 {
            bytes += 50000
            _ = estimator.estimate(
                completedBytes: bytes, totalBytes: total, now: now(Double(tick) * 0.5 + 0.5)
            )
        }
        // One more tick to close the window seeded at t = 0.5 (+ 5 s gone).
        bytes += 50000
        let estimate = estimator.estimate(completedBytes: bytes, totalBytes: total, now: now(6.5))

        // ~150 KB left at a real 100 KB/s → ~1.5 s. With the resume bug it
        // would be (300 + 550) KB / 5 s ≈ 170 KB/s → ~0.9 s.
        #expect(estimate != nil)
        if let estimate {
            #expect(estimate > 1.2 && estimate < 2.2, "estimate was \(estimate)")
        }
    }

    private func now(_ seconds: Double) -> ContinuousClock.Instant {
        ContinuousClock.now.advanced(by: .seconds(seconds))
    }
}
