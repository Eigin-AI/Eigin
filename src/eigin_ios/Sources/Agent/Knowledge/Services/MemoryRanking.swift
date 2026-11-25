import EiginSDK
import Foundation

/// Host date adaptation for portable memory ranking.
enum MemoryRanking {
    typealias SDK = EiginSDK.Experimental.Knowledge

    static let maximumAdjustment = 0.05
    static let maximumAccessCount = 16.0

    static func boost(
        accessCount: Double,
        lastAccessedAt: Date?,
        importance: Double,
        now: Date
    ) -> Double {
        SDK.memoryBoost(
            accessCount: accessCount, lastAccessedAt: lastAccessedAt?.timeIntervalSince1970,
            importance: importance, now: now.timeIntervalSince1970
        )
    }

    static func importanceLift(_ importance: Double) -> Double {
        SDK.importanceLift(importance)
    }

    static func activation(accessCount: Double, lastAccessedAt: Date?, now: Date) -> Double {
        SDK.memoryActivation(
            accessCount: accessCount, lastAccessedAt: lastAccessedAt?.timeIntervalSince1970,
            now: now.timeIntervalSince1970
        )
    }
}
