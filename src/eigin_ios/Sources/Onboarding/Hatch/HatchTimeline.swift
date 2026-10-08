import CoreGraphics
import Foundation

/// The agent's hatch, as pure functions of time in seconds. The green circle
/// with the mark breathes like it is working: it swells and gets agitated,
/// then contracts, and each contraction squeezes the mark. Three breaths, each
/// bigger, and the last squeezes the mark away; then it settles to a circle
/// with the agent's face in it. Everything reads one clock, so the moment can
/// be slowed or scrubbed.
///
/// Ported from the design gallery's `onboarding/hatch.ts`; keep the two in step.
enum HatchTimeline {
    /// A beat of empty screen, then the circle with the mark grows in.
    static let appears: TimeInterval = 0.45
    /// It has grown in and held a moment: the build-up begins.
    static let arrived = appears + 1.0
    /// The mark is gone: the blob settles to a circle and the face springs in.
    static let release = arrived + 4.0
    /// Everything has come to rest, the last ripple included.
    static let settled = release + 1.8
    /// The ripples have faded out completely: only now does the hatch move up.
    static let lands = release + 1.7

    /// The blob's size through the build-up: firm, then three breaths out and
    /// in, each bigger. A contraction is quick, a swell takes its time.
    static let breaths: [(at: TimeInterval, size: Double)] = [
        (arrived, 1),
        (arrived + 1.15, 1.14),
        (arrived + 1.5, 0.9),
        (arrived + 2.4, 1.2),
        (arrived + 2.75, 0.86),
        (arrived + 3.65, 1.24),
        (release, 0.8),
    ]

    /// The last contraction: the one that takes the mark away.
    private static let lastSwell = breaths[breaths.count - 2].at

    private static let grow = SpringCurve(duration: 0.6, bounce: 0.25)
    private static let settle = SpringCurve(duration: 0.6, bounce: 0.45)
    private static let pop = SpringCurve(duration: 0.5, bounce: 0.45)
    /// The release: quick and bouncy, so it lands with a snap.
    private static let snap = SpringCurve(duration: 0.35, bounce: 0.45)

    /// Whether the mark is gone and the face is coming in.
    static func released(_ t: TimeInterval) -> Bool {
        t >= release
    }

    /// The whole hatch growing in from nothing, after the empty beat.
    static func arrival(_ t: TimeInterval) -> (opacity: Double, scale: Double) {
        (clamp((t - appears) / 0.1), t < arrived ? max(grow(t - appears), 0) : 1)
    }

    /// The blob's size: the breaths, then a snap back out to the circle.
    static func size(_ t: TimeInterval) -> Double {
        if t >= release { return 0.8 + 0.2 * snap(t - release) }
        for i in 1 ..< breaths.count {
            let from = breaths[i - 1]
            let to = breaths[i]
            if t < to.at { return from.size + (to.size - from.size) * smooth(from.at, to.at, t) }
        }
        return 1
    }

    /// How agitated the blob is, 0–1. It steps up with each swell and firms up
    /// as it contracts, so the moves are biggest when it is most open.
    static func agitation(_ t: TimeInterval) -> Double {
        let level = 0.35 * smooth(breaths[0].at, breaths[1].at, t)
            + 0.3 * smooth(breaths[2].at, breaths[3].at, t)
            + 0.35 * smooth(breaths[4].at, breaths[5].at, t)
        let open = clamp((size(t) - 0.86) / (1.2 - 0.86))
        return level * (0.35 + 0.65 * open)
    }

    /// The face springs into the circle, untwisting as it lands. Sized rather
    /// than scaled by the caller, so the glyph stays sharp at every frame.
    static func face(_ t: TimeInterval) -> (scale: Double, rotate: Double, opacity: Double) {
        let settled = pop(t - release - 0.06)
        return (max(settled, 0), -14 * (1 - settled), t < release ? 0 : 1)
    }

    /// How far into the last breath, 0–1, eased in: the pace picks up toward the end.
    static func finale(_ t: TimeInterval) -> Double {
        pow(smooth(breaths[4].at, release, t), 2)
    }

    /// How worked up the blob is. `gain` exaggerates the thinking indicator's
    /// own forms (1 is as-is); `stretch` pulls it long one way; `inset` presses
    /// a couple of dents into it. All big and slow: a few large moves.
    private static func effort(_ t: TimeInterval)
        -> (gain: Double, stretch: Double, inset: Double)
    {
        let at = min(t, release)
        let working = agitation(at)
        let fluid = smooth(arrived, arrived + 0.6, at)
        let gain = fluid * (0.6 + 2 * working) + 0.8 * finale(at)
        let stretch = 0.03 * fluid + 0.17 * working + 0.05 * finale(at)
        let inset = 0.1 * working
        guard released(t) else { return (gain, stretch, inset) }
        // Settles back to the circle on a spring, wobbling once past round.
        let left = 1 - settle(t - release)
        return (gain * left, stretch * left, inset * left)
    }

    /// The thinking indicator's own choreography, so the blob reads as that one.
    private static let morph = MorphTimeline(gallerySeed: 0x5EED_A11C)
    private static let circle = MorphForm.all[0]

    /// The blob's outline at a unit radius, before the mark's floor: the
    /// thinking indicator's forms exaggerated, a long stretch swinging round
    /// and a couple of dents pressed in, sized by the breath alone.
    static func shape(_ t: TimeInterval, clock: Double) -> [CGPoint] {
        let (gain, stretch, inset) = effort(t)
        let figure = MorphFigure.of(forms: MorphForm.all, pose: morph.pose(at: clock), intensity: 1)
        let restWidth = Double(circle.size.width) / 2
        let restHeight = Double(circle.size.height) / 2
        let halfWidth: Double = restWidth + (figure.width / 2 - restWidth) * gain
        let halfHeight: Double = restHeight + (figure.height / 2 - restHeight) * gain
        // Turns with the morph's clock, so the swing quickens as the blob works.
        let swing = clock * 0.8
        let press = 1 - clock * 0.45
        let count = Double(figure.points.count)

        let shaped = figure.points.enumerated().map { i, p in
            let c = circle.points[i]
            let theta = Double(i) / count * 2 * .pi
            let long: Double = stretch * cos(2 * (theta - swing))
            let dents: Double = inset * cos(3 * theta + press)
            let bend: Double = 1 + long + dents
            let x: Double = (c.x + (p.x - c.x) * gain) * halfWidth * bend
            let y: Double = (c.y + (p.y - c.y) * gain) * halfHeight * bend
            return CGPoint(x: x, y: y)
        }

        // Exaggerating the morph exaggerates its forms' sizes too; only the
        // shape should be, so the size is the breath's alone.
        let mean = shaped.reduce(0) { $0 + hypot($1.x, $1.y) } / count
        let fit = size(t) / mean
        return shaped.map { CGPoint(x: $0.x * fit, y: $0.y * fit) }
    }

    /// The mark: carried and squeezed by the blob, as simulated in
    /// ``HatchSimulation``. The last contraction takes it away to nothing,
    /// ending on the release.
    static func mark(_ t: TimeInterval) -> HatchSimulation.Mark {
        var mark = HatchSimulation.frame(at: t).mark
        mark.scale *= 1 - pow(smooth(lastSwell, release, t), 3)
        return mark
    }

    /// The blob's outline, centred on 0. It starts as the exact circle, then
    /// breathes and works like the thinking indicator, only harder; on the
    /// release it snaps back to the circle. `swell` reaches the edge out at an
    /// angle, in units of the radius.
    static func blob(
        _ t: TimeInterval, radius: Double, swell: (Double) -> Double = { _ in 0 }
    ) -> [CGPoint] {
        let points = shape(t, clock: HatchSimulation.frame(at: t).clock).map { p in
            let reached = radius * (1 + swell(atan2(p.y, p.x)))
            return CGPoint(x: p.x * reached, y: p.y * reached)
        }
        if released(t) { return points }

        // Never dents in far enough to bare the mark, wherever it is and
        // however small it is now.
        let held = mark(t)
        let centre = CGPoint(x: held.x * radius, y: held.y * radius)
        let floor = radius * 0.86 * held.scale
        return points.map { p in
            let dx = p.x - centre.x
            let dy = p.y - centre.y
            let r = hypot(dx, dy)
            let kept = softMax(r, floor, radius * 0.08) / r
            return CGPoint(x: centre.x + dx * kept, y: centre.y + dy * kept)
        }
    }

    /// The radiating ripples: wobbly rings spreading from the release, like a
    /// drop landing in water.
    static func ripples(_ t: TimeInterval, radius: Double) -> [(
        points: [CGPoint],
        opacity: Double,
        width: Double
    )] {
        (0 ..< 3).compactMap { index in
            let i = Double(index)
            let into = (t - release - i * 0.11) / (1.1 + i * 0.15)
            guard into > 0, into < 1 else { return nil }
            let spread = easeOut(into)
            let size = radius * (1.05 + (1.6 - i * 0.3) * spread)
            let wobble = 0.035 * (1 - into)
            let phase = i * 2 + t * 2
            let points = (0 ..< 60).map { k in
                let theta = Double(k) / 60 * 2 * .pi
                let r = size * (1 + wobble * cos(3 * theta + phase))
                return CGPoint(x: r * cos(theta), y: r * sin(theta))
            }
            return (points, 0.85 * pow(1 - into, 1.5), 5 * (1 - spread) + 1)
        }
    }

    // MARK: - Easing

    /// A max with a rounded corner `k` wide, so a floor never leaves a flat.
    private static func softMax(_ a: Double, _ b: Double, _ k: Double) -> Double {
        (a + b + sqrt((a - b) * (a - b) + k * k)) / 2
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func easeOut(_ value: Double) -> Double {
        1 - pow(1 - value, 3)
    }

    static func smooth(_ from: Double, _ to: Double, _ t: Double) -> Double {
        let x = clamp((t - from) / (to - from))
        return x * x * (3 - 2 * x)
    }
}
