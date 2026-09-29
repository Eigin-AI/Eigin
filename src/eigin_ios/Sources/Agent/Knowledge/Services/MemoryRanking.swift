import Foundation

/// Cognitive-signal boosts layered on top of cue relevance when ranking memories.
///
/// Relevance (semantic + keyword match) stays the primary signal. On top of it we
/// add two query-independent boosts computed from a memory's stored scalars:
///
/// - **Base-level activation** — recency × frequency of use. A memory used often
///   and recently is stronger. Inspired by ACT-R's activation model.
/// - **Importance** — a safety net for rare-but-critical facts, centred so the
///   default (`0.5`) is neutral.
///
/// A *neutral* memory (never accessed, default importance) contributes exactly
/// zero, so relevance alone still orders fresh, untouched knowledge. Weights are
/// deliberately small so boosts reorder near-ties rather than override strong
/// cue matches. They're first guesses — tune in the offline sandbox.
enum MemoryRanking {
    /// Weight on the recency × frequency activation term (max contribution).
    static let activationWeight = 0.3

    /// Weight on the importance term. Sized so a rare-but-critical fact can
    /// clear everyday high-frequency trivia — the safety net has to win.
    static let importanceWeight = 0.35

    /// Half-life in days for decaying the access count: accesses this many
    /// days old count half as much toward frequency as current ones.
    static let recencyHalfLifeDays = 14.0

    /// Frequency saturation constant. Larger = frequency saturates more slowly,
    /// so each additional access keeps mattering for longer.
    static let frequencySaturation = 4.0

    /// Combined boost added to a memory's relevance score. Zero for a neutral
    /// (never-accessed, default-importance) memory.
    static func boost(accessCount: Double, lastAccessedAt: Date?, importance: Double, now: Date)
        -> Double
    {
        activationWeight * activation(
            accessCount: accessCount, lastAccessedAt: lastAccessedAt, now: now
        )
            + importanceWeight * importanceLift(importance)
    }

    /// Importance mapped to a boost multiplier, centred on the default `0.5`.
    ///
    /// Asymmetric on purpose: a strong lift above neutral (so critical facts
    /// surface even when rarely used) and only a gentle penalty below (so a
    /// low-stakes memory fades but isn't buried). Above: `[0, +1]`. Below:
    /// `[-0.25, 0]`.
    static func importanceLift(_ importance: Double) -> Double {
        let delta = importance - 0.5
        return delta >= 0 ? delta * 2 : delta * 0.5
    }

    /// Recency × frequency activation in `[0, 1)`. Zero when never accessed.
    ///
    /// The stored access count is decayed by the recency half-life — an access
    /// 14 days ago counts half, 28 days ago a quarter — so frequency measures
    /// *recent* use, and a memory whose accesses stop fades toward zero
    /// without needing another access. Decayed count then saturates, so each
    /// additional access matters less as usage accumulates.
    static func activation(accessCount: Double, lastAccessedAt: Date?, now: Date) -> Double {
        guard accessCount > 0, let last = lastAccessedAt else { return 0 }

        let elapsedDays = max(0, now.timeIntervalSince(last)) / 86400
        let effectiveCount = accessCount * exp(-elapsedDays / recencyHalfLifeDays * log(2))
        return effectiveCount / (effectiveCount + frequencySaturation)
    }
}
