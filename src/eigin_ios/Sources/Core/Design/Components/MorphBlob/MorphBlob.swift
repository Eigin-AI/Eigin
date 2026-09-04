import SwiftUI

/// The morphing blob: scales in and wobbles through the form library, pulled
/// toward a still circle by `intensity`. Fully time-derived — the shape is
/// recomputed from `shownAt` every frame, so the view can be torn down and
/// rebuilt without glitching.
///
/// Fills whichever frame it's given: forms are scaled relative to the largest
/// library form, so any slot size works. Under reduce motion it renders a
/// still full-size circle.
struct MorphBlob: View {
    /// Anchors the choreography (cycle, entry, breath). Also seeds it, so
    /// every appearance gets a fresh cycle order.
    var shownAt: Date
    /// How much of the wobble is showing; ramps in and out over time.
    var intensity: MorphIntensity
    /// Time multiplier on the morphing: below 1 makes the wobble slower, for
    /// big blobs that shouldn't dance as briskly as the chat-sized one.
    var tempo: Double = 1
    /// Seconds to hold invisible before the scale-in entry plays — for
    /// entries that would otherwise hide behind a transition.
    var entryDelay: TimeInterval = 0
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seeded choreography for this appearance. Derived from `shownAt` on
    /// every evaluation rather than stored, so the blob never depends on an
    /// appearance callback that SwiftUI may skip when a view is rebuilt.
    private var timeline: MorphTimeline {
        MorphTimeline(seed: UInt64(bitPattern: Int64(shownAt.timeIntervalSince1970 * 1000)))
    }

    /// The largest native form size; drawing scales figures off it.
    private static let maxFormSize = MorphForm.all
        .map { max($0.size.width, $0.size.height) }.max() ?? 1

    /// Share of the frame the largest form occupies — margin left for the
    /// entry overshoot and breath.
    private static let fill = 0.875

    /// Scale forms into a frame of `slot` points.
    private static func scale(in slot: Double) -> Double {
        slot * fill / maxFormSize
    }

    /// The smallest form's diameter when drawn in a frame of `slot` points —
    /// the inner edge content on top of the blob must fit inside.
    static func minDiameter(in slot: Double) -> Double {
        let smallest = MorphForm.all
            .map { min($0.size.width, $0.size.height) }.min() ?? maxFormSize
        return smallest * scale(in: slot)
    }

    var body: some View {
        // An outer gate throttles the whole thing when nothing is moving —
        // on the call screen a settled circle is the normal state, and
        // redrawing it at display rate all call long is waste. The gate runs
        // a little fast so it spots the next ramp promptly; the inner
        // schedule animates at full rate only while something moves.
        TimelineView(.animation(minimumInterval: 0.25)) { gate in
            let lively = isLively(at: gate.date)
            TimelineView(.animation(minimumInterval: reduceMotion
                    ? 0.5 : lively ? nil : 0.25))
            { context in
                Canvas { canvas, frame in
                    canvas.fill(path(in: frame, at: context.date), with: .color(color))
                }
            }
        }
    }

    /// Whether anything is moving right now: the entry is playing, or the
    /// wobble is showing at any level.
    private func isLively(at date: Date) -> Bool {
        if date.timeIntervalSince(shownAt) < entryDelay + MorphTimeline.entryDuration {
            return true
        }
        return reduceMotion ? false : intensity.value(at: date) > 0
    }

    private func path(in frame: CGSize, at date: Date) -> Path {
        let timeline = timeline
        let size = frame
        let t = date.timeIntervalSince(shownAt)

        let pose = reduceMotion ? MorphTimeline.Pose(from: 0, to: 0, progress: 0) : timeline
            .pose(at: t * tempo)
        let wobble = reduceMotion ? 0 : intensity.value(at: date)
        let figure = MorphFigure.of(forms: MorphForm.all, pose: pose, intensity: wobble)

        // Entry overshoot plays on any appearance, after the delay; the
        // breath rides along with the wobble so calm mode is still.
        let entry = reduceMotion ? 1 : timeline.entryScale(at: t - entryDelay)
        let breath = reduceMotion ? 1 : 1 + (timeline.breath(at: t) - 1) * wobble

        let scale = Self.scale(in: min(size.width, size.height))
        let halfWidth = figure.width / 2 * scale * entry * breath
        let halfHeight = figure.height / 2 * scale * entry * breath
        if halfWidth <= 0 || halfHeight <= 0 { return Path() }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let samples = figure.points.map { point in
            CGPoint(x: center.x + point.x * halfWidth, y: center.y + point.y * halfHeight)
        }
        return SplineOutline.path(through: samples)
    }
}

/// Closed Catmull-Rom spline: a smooth outline through evenly spaced samples.
enum SplineOutline {
    static func path(through points: [CGPoint]) -> Path {
        var path = Path()
        let count = points.count
        guard count > 2 else { return path }
        path.move(to: points[0])
        for i in 0 ..< count {
            let p0 = points[(i - 1 + count) % count]
            let p1 = points[i]
            let p2 = points[(i + 1) % count]
            let p3 = points[(i + 2) % count]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Intensity ramp") {
    TimelineView(.animation) { context in
        let date = context.date
        VStack(spacing: Spacing.n24) {
            ForEach(0 ..< 4) { i in
                MorphBlob(
                    shownAt: date.addingTimeInterval(-0.25 * Double(i) - 1),
                    intensity: MorphIntensity(
                        engaged: true, changedAt: date.addingTimeInterval(-0.4 * Double(i))
                    ),
                    color: Color(red: 0.655, green: 0.690, blue: 0.306)
                )
                .frame(width: 80, height: 80)
            }
        }
    }
    .padding(Spacing.n32)
    .background(Color(white: 0.09))
}
