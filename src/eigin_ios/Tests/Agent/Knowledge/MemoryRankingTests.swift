@testable import Eigin
import Foundation
import Testing

@Suite("MemoryRanking")
struct MemoryRankingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func activation(
        accessCount: Double,
        daysSinceLastAccess: Double?,
        now: Date
    ) -> Double {
        MemoryRanking.activation(
            accessCount: accessCount,
            lastAccessedAt: daysSinceLastAccess.map {
                now.addingTimeInterval(-$0 * 86400)
            },
            now: now
        )
    }

    /// Approximate equality for float assertions over exp()-based decay.
    private func isApprox(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
        abs(a - b) < tolerance
    }

    @Test func zeroCountIsZero() {
        #expect(isApprox(
            MemoryRanking.activation(accessCount: 0, lastAccessedAt: now, now: now), 0
        ))
    }

    @Test func nilLastAccessIsZero() {
        #expect(isApprox(
            MemoryRanking.activation(accessCount: 10, lastAccessedAt: nil, now: now), 0
        ))
    }

    @Test func saturatesBelowOne() {
        let act = MemoryRanking.activation(
            accessCount: 1_000_000, lastAccessedAt: now, now: now
        )
        #expect(act < 1.0)
        #expect(isApprox(act, 0.8))
    }

    @Test func oneHalfLifeHalvesTheCount() {
        // Count 4, fresh → 4/(4+4) = 0.5. After one half-life the count is
        // 2 → 2/(2+4) = 1/3.
        #expect(isApprox(activation(accessCount: 4, daysSinceLastAccess: 0, now: now), 0.5))
        #expect(isApprox(activation(accessCount: 4, daysSinceLastAccess: 14, now: now), 1.0 / 3.0))
    }

    @Test func starvedAccessHistoryFadesTowardZero() {
        // After ten half-lives an old access history is effectively gone.
        let act = activation(accessCount: 1_000_000, daysSinceLastAccess: 140, now: now)
        #expect(act < 0.01)
    }

    @Test func decaysMonotonically() {
        var last = activation(accessCount: 10, daysSinceLastAccess: 0, now: now)
        for days in stride(from: 7.0, through: 112.0, by: 7.0) {
            let act = activation(accessCount: 10, daysSinceLastAccess: days, now: now)
            #expect(act < last)
            last = act
        }
    }

    @Test func historicalCountCapAppliesBeforeDecay() {
        for days in [0.0, 14, 28, 140] {
            #expect(isApprox(
                activation(accessCount: 1_000_000, daysSinceLastAccess: days, now: now),
                activation(
                    accessCount: MemoryRanking.maximumAccessCount,
                    daysSinceLastAccess: days,
                    now: now
                )
            ))
        }
    }

    @Test func outOfRangeImportanceCannotEscapeAdjustmentBound() {
        for importance in [-100.0, 0, 0.5, 1, 100] {
            let boost = MemoryRanking.boost(
                accessCount: 1_000_000, lastAccessedAt: now, importance: importance, now: now
            )
            #expect(abs(boost) <= MemoryRanking.maximumAdjustment)
        }
    }
}
