import Foundation

/// What the blob draws at a moment: normalized sample points and the extents
/// they scale into. The seeded choreography is pulled toward the resting
/// circle by `intensity`, so 0 renders a plain still circle and 1 the full
/// wobble's current pose.
struct MorphFigure: Equatable {
    let points: [CGPoint]
    let width: Double
    let height: Double

    /// Blends the pose between its two forms, then toward the resting circle
    /// (`forms[0]`) by `intensity` — a plain linear pull in point space.
    static func of(
        forms: [MorphForm], pose: MorphTimeline.Pose, intensity: Double
    ) -> MorphFigure {
        let amount = min(max(intensity, 0), 1)
        let circle = forms[0]
        let from = forms[pose.from]
        let to = forms[pose.to]
        let count = MorphForm.pointCount

        let progress = pose.progress
        let width = lerp(from.size.width, to.size.width, progress)
        let height = lerp(from.size.height, to.size.height, progress)

        var blended: [CGPoint] = []
        blended.reserveCapacity(count)
        for i in 0 ..< count {
            let a = from.points[i % count]
            let b = to.points[i % count]
            let c = circle.points[i]
            blended.append(CGPoint(
                x: c.x + (a.x + (b.x - a.x) * progress - c.x) * amount,
                y: c.y + (a.y + (b.y - a.y) * progress - c.y) * amount
            ))
        }
        return MorphFigure(
            points: blended,
            width: circle.size.width + (width - circle.size.width) * amount,
            height: circle.size.height + (height - circle.size.height) * amount
        )
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
