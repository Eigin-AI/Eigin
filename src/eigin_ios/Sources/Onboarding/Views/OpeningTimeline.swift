import SwiftUI

/// The onboarding opening, as pure functions of time in seconds. Ported from
/// the design gallery's `onboarding/opening.ts`, which tells the story; keep
/// the two in step.
enum OpeningTimeline {
    /// Where the avatar is at a moment of the opening.
    struct Pose: Equatable {
        /// From screen centre (0) to the avatar's slot (1).
        var rise: Double
        /// From the launch mark's size to 1.
        var scale: Double
        /// How far through its breath the green circle is, 0–1.
        var breath: Double
        /// Tall above 0, wide below.
        var stretch: Double

        static let settled = Pose(rise: 1, scale: 1, breath: 0, stretch: 0)
    }

    /// How long the mark holds at centre, picking up from the launch screen.
    static let hold: TimeInterval = 0.4
    /// One breath, like the start of the hatch, snap-back included.
    static let breathDuration: TimeInterval = 1.75
    /// The breath, in seconds into it: a slow swell, then a quick squeeze
    /// until the release.
    private static let swell: TimeInterval = 0.9
    private static let release = swell + 0.3
    /// The rise from centre to the avatar's place, starting on the release.
    private static let riseDuration: TimeInterval = 0.8
    private static let risesAt = hold + release
    /// Done moving, the spring's tail included.
    static let opened = max(hold + breathDuration, risesAt + riseDuration * 2)
    /// When the welcome title starts: as the rise settles, not after it.
    static let titleAt = risesAt + riseDuration * 0.6

    private static let swollen = 1.08
    private static let squeezed = 0.93
    private static let rise = SpringCurve(duration: riseDuration, bounce: 0.2)
    /// The hatch's release springs: a snap out, a bouncy settle of the shape.
    private static let snap = SpringCurve(duration: 0.35, bounce: 0.45)
    private static let settle = SpringCurve(duration: 0.6, bounce: 0.45)

    /// The pose `t` seconds in. `launchScale` makes the vessel match the
    /// launch screen's mark.
    static func pose(at t: TimeInterval, launchScale: Double) -> Pose {
        let settled = rise(t - risesAt)
        let down = crouch(t)
        return Pose(
            // Pressed down a touch in the crouch, the push-off for the jump.
            rise: settled - 0.02 * max(down, 0),
            scale: launchScale + (1 - launchScale) * settled,
            breath: clamp((t - hold) / breathDuration),
            // Squashed wide by the crouch, pulled tall by the speed of the rise.
            stretch: -0.09 * down + 0.14 * riseSpeed(t - risesAt)
        )
    }

    /// The green circle `progress` (0–1) through its breath: it swells as it
    /// stretches long and lumpy, squeezes in quickly, then snaps back out to
    /// the circle. On a unit circle centred on 0.
    static func outline(_ progress: Double) -> [CGPoint] {
        guard progress > 0, progress < 1 else { return circle { _ in 1 } }
        let t = progress * breathDuration
        let size = breathSize(t)
        // Most worked up when most open; firms up as it squeezes, then lets go.
        let open = clamp((size - squeezed) / (swollen - squeezed))
        let build = smooth(0, swell * 0.6, t)
        let left = t < release ? 1 : 1 - settle(t - release)
        let stretch = (0.02 + 0.08 * open) * build * left
        let inset = 0.045 * open * build * left
        // The long axis swings round as it works.
        let swing = 0.4 + 1.1 * t
        let press = 1 - 0.8 * t
        return circle { theta in
            size * (1 + stretch * cos(2 * (theta - swing)) + inset * cos(3 * theta + press))
        }
    }

    /// The brand mark's scale `progress` through the breath. A press, not a
    /// shrink: the mark gives about half as much as the blob.
    static func markScale(_ progress: Double) -> Double {
        guard progress > 0, progress < 1 else { return 1 }
        return 1 - 0.55 * (1 - min(1, breathSize(progress * breathDuration)))
    }

    // MARK: - Moves

    /// The blob's size, as a share of its radius, `t` seconds into the breath.
    private static func breathSize(_ t: TimeInterval) -> Double {
        if t < swell { return 1 + (swollen - 1) * smooth(0, swell, t) }
        if t < release { return swollen + (squeezed - swollen) * smooth(swell, release, t) }
        return squeezed + (1 - squeezed) * snap(t - release)
    }

    /// How deep the crouch is: in through the squeeze, out on the release,
    /// overshooting.
    private static func crouch(_ t: TimeInterval) -> Double {
        if t < risesAt { return smooth(hold + swell, risesAt, t) }
        return 1 - snap(t - risesAt)
    }

    /// The rise's speed `t` seconds into it, as a share of its fastest.
    private static func riseSpeed(_ t: TimeInterval) -> Double {
        velocity(t) / peakSpeed
    }

    private static let peakSpeed = (0 ..< 200).map { velocity(Double($0) / 100) }.max() ?? 1

    private static func velocity(_ t: TimeInterval) -> Double {
        let h = 1.0 / 240
        return (rise(t + h) - rise(t - h)) / (2 * h)
    }

    private static func circle(_ radius: (Double) -> Double) -> [CGPoint] {
        let count = MorphForm.pointCount
        return (0 ..< count).map { i in
            let theta = Double(i) / Double(count) * 2 * .pi
            let r = radius(theta)
            return CGPoint(x: r * cos(theta), y: r * sin(theta))
        }
    }

    private static func clamp(_ value: Double) -> Double {
        HatchTimeline.clamp(value)
    }

    private static func smooth(_ from: Double, _ to: Double, _ t: Double) -> Double {
        HatchTimeline.smooth(from, to, t)
    }
}

/// The green circle through the opening's breath — one swell and release,
/// the way the hatch starts — pulled tall or wide by `stretch` while keeping
/// its area. At rest (breath 0) it is the true circle.
struct BreathingCircle: Shape {
    /// How far through the breath, 0–1: it drives the circle's size and shape.
    var breath: Double
    var stretch: Double

    func path(in rect: CGRect) -> Path {
        // At rest it is the true circle, matching the launch screen exactly.
        let resting = breath <= 0 || breath >= 1
        if resting, stretch == 0 { return Path(ellipseIn: rect) }
        let radius = min(rect.width, rect.height) / 2
        let points = OpeningTimeline.outline(breath).map {
            CGPoint(
                x: rect.midX + $0.x / (1 + stretch) * radius,
                y: rect.midY + $0.y * (1 + stretch) * radius
            )
        }
        return SplineOutline.path(through: points)
    }
}
