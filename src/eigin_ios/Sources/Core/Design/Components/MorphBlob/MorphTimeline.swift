import Foundation

/// Deterministic timeline for the morphing blob.
///
/// Everything the blob does is a pure function of elapsed time plus a seed:
/// the library position (pose), the scale-in on first appearance, and the
/// slow breath. No animation state is stored, so the blob can be torn down
/// and rebuilt — pushed down the feed by tool cards, say — and lands on
/// exactly the same frame it left.
struct MorphTimeline: Equatable {
    /// Which two forms a moment sits between, and how far between them.
    /// `from == to` means holding a single form.
    struct Pose: Equatable {
        let from: Int
        let to: Int
        let progress: Double
    }

    // Tuned against the design prototype ("Pose, settle, speak up"), then
    // re-tuned by eye: faster travel, and a mixed rhythm so the blob never
    // settles into a metronome.
    static let initialHold: TimeInterval = 0.6
    static let entryDuration: TimeInterval = 0.4
    /// Default breath: a barely visible swell, scale only, never a drift.
    /// Callers on other stages can pass their own pulse.
    static let breathScaleAmplitude = 0.022
    static let breathPeriod: TimeInterval = 4.6

    private(set) var breathScaleAmplitude: Double
    private(set) var breathPeriod: TimeInterval

    /// Travel/hold recipe for one segment. Mixed weights give bursts of quick
    /// changes punctuated by longer settles — fast, fast, slow rather than
    /// tick, tock, tick.
    enum Rhythm: CaseIterable {
        case quick
        case medium
        case settle

        var travel: ClosedRange<TimeInterval> {
            switch self {
            case .quick: 0.42 ... 0.55
            case .medium: 1.1 ... 1.35
            case .settle: 1.25 ... 1.6
            }
        }

        var weight: Double {
            switch self {
            case .quick: 0.35
            case .medium: 0.4
            case .settle: 0.25
            }
        }
    }

    /// Travel easing: a slight ease — the morph glides without a spring's
    /// bounce, which suits the longer continuous transitions.
    static let travelEasing = CubicBezierEasing(x1: 0.37, y1: 0, x2: 0.63, y2: 1)
    /// Prototype entry easing: cubic-bezier(.32, 1.4, .5, 1) — overshoots, settles.
    static let entryEasing = CubicBezierEasing(x1: 0.32, y1: 1.4, x2: 0.5, y2: 1)

    /// Library positions the blob travels through — one seeded cycle that
    /// starts on the circle, visits every form once in shuffled order, and
    /// returns to the circle, so looping it is seamless.
    private(set) var sequence: [Int]
    /// Travel durations per travelled segment (holds stay zero).
    private(set) var segments: [Segment]

    struct Segment: Equatable {
        let travel: TimeInterval
    }

    /// Seeded so the same turn always produces the same choreography.
    /// `formCount` fixes the library the cycle runs through — callers
    /// drawing a different form set must pass its count.
    init(
        seed: UInt64 = 0x5EED_A11C,
        formCount: Int = MorphForm.all.count,
        breathScaleAmplitude: Double = MorphTimeline.breathScaleAmplitude,
        breathPeriod: TimeInterval = MorphTimeline.breathPeriod
    ) {
        self.seed = seed
        self.breathScaleAmplitude = breathScaleAmplitude
        self.breathPeriod = breathPeriod
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        func randomUnit() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state >> 11) / Double(1 << 53)
        }

        let count = formCount
        var generator = SeededGenerator(state: state)
        sequence = [0] + (1 ..< count).shuffled(using: &generator) + [0]

        segments = []
        for _ in 0 ..< sequence.count - 1 {
            let rhythm = weightedRhythm(randomUnit())
            segments.append(Segment(
                travel: rhythm.travel.lowerBound
                    + randomUnit() * (rhythm.travel.upperBound - rhythm.travel.lowerBound)
            ))
        }
    }

    /// Picks a rhythm by weight; `roll` is uniform in [0, 1).
    private func weightedRhythm(_ roll: Double) -> Rhythm {
        var cumulative = 0.0
        for rhythm in Rhythm.allCases {
            cumulative += rhythm.weight
            if roll < cumulative { return rhythm }
        }
        return Rhythm.allCases.last ?? .medium
    }

    private let seed: UInt64

    /// The blob's library position at `t` seconds after it appeared.
    func pose(at t: TimeInterval) -> Pose {
        guard t >= Self.initialHold, !segments.isEmpty else {
            return Pose(from: 0, to: 0, progress: 0)
        }
        // Long waits loop the pre-generated choreography rather than freezing;
        // the wrap lands on the circle the blob entered with.
        var remaining = t - Self.initialHold
        let totalDuration = segments.reduce(0) { $0 + $1.travel }
        if totalDuration > 0 {
            remaining = remaining.truncatingRemainder(dividingBy: totalDuration)
        }
        for (i, segment) in segments.enumerated() {
            let from = sequence[i]
            let to = sequence[i + 1]
            if remaining < segment.travel {
                return Pose(
                    from: from,
                    to: to,
                    progress: Self.travelEasing(remaining / segment.travel)
                )
            }
            remaining -= segment.travel
        }
        // Numerical edge at the wrap seam.
        return Pose(from: 0, to: 0, progress: 0)
    }

    /// Scale-in progress for the blob's first seconds. Overshoots slightly
    /// on the way to 1, mirroring the prototype's pop.
    func entryScale(at t: TimeInterval) -> Double {
        guard t > 0 else { return 0 }
        guard t < Self.entryDuration else { return 1 }
        return Self.entryEasing(t / Self.entryDuration)
    }

    /// The breath: a barely visible swell, scale only, never a drift.
    func breath(at t: TimeInterval) -> Double {
        let phase = t / breathPeriod * 2 * .pi + .pi / 2
        return 1 + breathScaleAmplitude * sin(phase)
    }
}

/// Deterministic RNG for form selection, seeded from the timeline seed.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
