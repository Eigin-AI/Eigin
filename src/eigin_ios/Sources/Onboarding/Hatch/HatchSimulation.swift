import CoreGraphics
import Foundation

/// The hatch simulated once, at 120 steps a second. The mark is a thing in the
/// dough: carried with the blob's mass, leaning where it goes, and squeezed as
/// it contracts, each on a spring, so it lags the blob and gives a little as it
/// recovers. Pure in time all the same: every frame is a lookup.
enum HatchSimulation {
    /// The mark, in units of the blob's radius and degrees.
    struct Mark: Equatable {
        var x: Double
        var y: Double
        var scale: Double
        var rotate: Double
    }

    struct Frame {
        /// The morph's clock: faster the more agitated, about 6× by the release.
        let clock: Double
        let mark: Mark
    }

    private static let step = 1.0 / 120
    /// How far the mark may be carried off centre, in units of the blob's radius.
    private static let drift = 0.11

    static func frame(at t: TimeInterval) -> Frame {
        frames[min(max(Int((t / step).rounded()), 0), frames.count - 1)]
    }

    /// Computes the frames ahead of the reveal, so its first render isn't the
    /// one paying for the whole simulation.
    static func prewarm() {
        Task.detached { _ = frames }
    }

    private static let frames: [Frame] = {
        typealias T = HatchTimeline
        var out: [Frame] = []
        var clock = MorphTimeline.initialHold
        var x = Spring(value: 0)
        var y = Spring(value: 0)
        var scale = Spring(value: 1)
        var lean = Spring(value: 0)
        var t = 0.0
        while t <= T.settled + step {
            if t > T.arrived {
                let now = min(t, T.release)
                clock += step * (1 + 2 * T.agitation(now) + 3 * T.finale(now))
            }
            let mass = centroid(T.shape(t, clock: clock))
            // Carried with the mass, but never far off centre.
            let reach = min(1, drift / max(hypot(mass.x, mass.y), 1e-6))
            x.follow(mass.x * reach, hz: 4, damping: 0.55)
            y.follow(mass.y * reach, hz: 4, damping: 0.55)
            // A press, not a shrink: the mark gives about half as much as the blob.
            scale.follow(1 - 0.55 * (1 - min(1, T.size(t))), hz: 4.5, damping: 0.4)
            lean.follow(40 * mass.x, hz: 3, damping: 0.5)
            out.append(Frame(
                clock: clock,
                mark: Mark(x: x.value, y: y.value, scale: scale.value, rotate: lean.value)
            ))
            t += step
        }
        return out
    }()

    /// Where an outline's mass sits: the centroid of the area it encloses.
    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        var area = 0.0
        var x = 0.0
        var y = 0.0
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            let cross = a.x * b.y - b.x * a.y
            area += cross
            x += (a.x + b.x) * cross
            y += (a.y + b.y) * cross
        }
        return area == 0 ? .zero : CGPoint(x: x / (3 * area), y: y / (3 * area))
    }

    /// A damped spring stepped toward a target, at `hz` with `damping` (1 is critical).
    private struct Spring {
        var value: Double
        var velocity = 0.0

        mutating func follow(_ target: Double, hz: Double, damping: Double) {
            let omega = 2 * .pi * hz
            let force = omega * omega * (target - value) - 2 * damping * omega * velocity
            velocity += force * HatchSimulation.step
            value += velocity * HatchSimulation.step
        }
    }
}

/// A SwiftUI `.spring(duration:bounce:)` as a function of time: 0 at rest at
/// the start, settling on 1, overshooting on the way when it bounces.
struct SpringCurve {
    let duration: Double
    let bounce: Double

    func callAsFunction(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * .pi / duration
        let damping = 1 - bounce
        if damping >= 1 { return 1 - (1 + omega * t) * exp(-omega * t) }
        let damped = omega * sqrt(1 - damping * damping)
        let decay = exp(-damping * omega * t)
        return 1 - decay * (cos(damped * t) + damping * omega / damped * sin(damped * t))
    }
}
