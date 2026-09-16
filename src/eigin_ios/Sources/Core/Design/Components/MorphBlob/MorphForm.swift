import SwiftUI

/// One form in the blob's library.
///
/// Any closed single-subpath outline becomes a form: it is flattened to a
/// dense polyline and resampled to a fixed number of equidistant points.
/// That shared point count — with matched winding and start point — is what
/// lets any form glide into any other without a cut.
struct MorphForm: Equatable {
    /// Sample points every form carries — the invariant behind morphing.
    static let pointCount = 60

    /// Points normalised to [-1, 1], clockwise, starting nearest the positive
    /// x axis so consecutive forms tween without spinning.
    let points: [CGPoint]
    /// Native point size the normalised geometry scales into.
    let size: CGSize

    /// Builds a form from any closed single-subpath path.
    init(path: Path, size: CGSize) {
        self.size = size
        points = Self.prepare(Self.flatten(path))
    }

    // MARK: Library

    /// A family of near-circles — different weightings and slight wobbles,
    /// like one hand-drawn circle shifting its weight between imperfect
    /// tracings. The one place to add, remove or reorder forms.
    static let all: [MorphForm] = [
        // The resting circle.
        MorphForm(path: FormPath.ellipse(), size: CGSize(width: 32, height: 32)),
        // Slightly smaller — a caught breath.
        MorphForm(path: FormPath.ellipse(), size: CGSize(width: 27, height: 27)),
        // Pulled out to the right.
        MorphForm(
            path: FormPath.blob([(lobes: 1, amount: 0.13, phase: .zero)]),
            size: CGSize(width: 34, height: 34)
        ),
        // Weighted toward the upper left.
        MorphForm(
            path: FormPath.blob([(lobes: 1, amount: 0.12, phase: .degrees(200))]),
            size: CGSize(width: 34, height: 34)
        ),
        // Uneven: a hand-drawn wobble, heavier low-left.
        MorphForm(
            path: FormPath.blob([
                (lobes: 1, amount: 0.11, phase: .degrees(35)),
                (lobes: 2, amount: 0.06, phase: .degrees(110)),
            ]),
            size: CGSize(width: 33, height: 33)
        ),
        // Bottom-weighted with a subtly dented side.
        MorphForm(
            path: FormPath.blob([
                (lobes: 1, amount: 0.14, phase: .degrees(90)),
                (lobes: 3, amount: 0.05, phase: .zero),
            ]),
            size: CGSize(width: 34, height: 34)
        ),
        // Tilted oval.
        MorphForm(
            path: FormPath.blob([(lobes: 2, amount: 0.13, phase: .degrees(30))]),
            size: CGSize(width: 33, height: 33)
        ),
        // Pulling harder: leaning lower-right.
        MorphForm(
            path: FormPath.blob([(lobes: 1, amount: 0.17, phase: .degrees(310))]),
            size: CGSize(width: 35, height: 35)
        ),
        // Pulling harder: a stretchier oval.
        MorphForm(
            path: FormPath.blob([(lobes: 2, amount: 0.14, phase: .degrees(70))]),
            size: CGSize(width: 35, height: 35)
        ),
        // Another uneven wobble, heavier to the left.
        MorphForm(
            path: FormPath.blob([
                (lobes: 1, amount: 0.13, phase: .degrees(150)),
                (lobes: 2, amount: 0.08, phase: .degrees(20)),
            ]),
            size: CGSize(width: 33, height: 33)
        ),
        // Pulled toward the lower left.
        MorphForm(
            path: FormPath.blob([(lobes: 1, amount: 0.15, phase: .degrees(120))]),
            size: CGSize(width: 34, height: 34)
        ),
        // Wide oval with a light wobble.
        MorphForm(
            path: FormPath.blob([
                (lobes: 2, amount: 0.12, phase: .degrees(10)),
                (lobes: 1, amount: 0.05, phase: .degrees(200)),
            ]),
            size: CGSize(width: 35, height: 35)
        ),
        // Strong pull to the upper right with a soft dent opposite.
        MorphForm(
            path: FormPath.blob([
                (lobes: 1, amount: 0.16, phase: .degrees(30)),
                (lobes: 3, amount: 0.05, phase: .degrees(90)),
            ]),
            size: CGSize(width: 35, height: 35)
        ),
        // Wobbly, heavier to the left with a high-frequency dent.
        MorphForm(
            path: FormPath.blob([
                (lobes: 1, amount: 0.12, phase: .degrees(300)),
                (lobes: 3, amount: 0.07, phase: .degrees(150)),
            ]),
            size: CGSize(width: 33, height: 33)
        ),
    ]

    /// A deeper set for small stages: the same hand-drawn language with the
    /// volume up — strong pulls, real dents and silhouette shifts, so the
    /// morphing reads at a glance at wrist size instead of whispering. The
    /// resting circle stays first: it is the pull target.
    static let bold: [MorphForm] = [
        // The resting circle.
        MorphForm(path: FormPath.ellipse(), size: CGSize(width: 32, height: 32)),
        // Pulled hard to the right.
        MorphForm(
            path: FormPath.blob([(lobes: 1, amount: 0.30, phase: .zero)]),
            size: CGSize(width: 38, height: 38)
        ),
        // Pulled hard to the upper left.
        MorphForm(
            path: FormPath.blob([(lobes: 1, amount: 0.30, phase: .degrees(200))]),
            size: CGSize(width: 38, height: 38)
        ),
        // A strong tilted oval.
        MorphForm(
            path: FormPath.blob([(lobes: 2, amount: 0.28, phase: .degrees(30))]),
            size: CGSize(width: 37, height: 37)
        ),
        // A trefoil wobble.
        MorphForm(
            path: FormPath.blob([(lobes: 3, amount: 0.20, phase: .degrees(90))]),
            size: CGSize(width: 34, height: 34)
        ),
        // Pulled lower-left with a dent opposite.
        MorphForm(
            path: FormPath.blob([
                (lobes: 1, amount: 0.34, phase: .degrees(120)),
                (lobes: 3, amount: 0.10, phase: .zero),
            ]),
            size: CGSize(width: 38, height: 38)
        ),
        // A rounded square — a real silhouette shift.
        MorphForm(
            path: FormPath.polygon(sides: 4, corner: 0.4, rotation: .degrees(20)),
            size: CGSize(width: 36, height: 36)
        ),
        // A rounded triangle — the most severe shape change in the set.
        MorphForm(
            path: FormPath.polygon(sides: 3, radii: [1, 1.1, 1], corner: 0.35, rotation: .zero),
            size: CGSize(width: 32, height: 32)
        ),
        // A capsule — long and thin against everything round.
        MorphForm(
            path: FormPath.stadium(width: 40, height: 24),
            size: CGSize(width: 40, height: 24)
        ),
        // Stretchy and wobbly.
        MorphForm(
            path: FormPath.blob([
                (lobes: 2, amount: 0.32, phase: .degrees(70)),
                (lobes: 5, amount: 0.06, phase: .zero),
            ]),
            size: CGSize(width: 36, height: 36)
        ),
        // A caught breath — small, for scale contrast.
        MorphForm(
            path: FormPath.blob([(lobes: 1, amount: 0.22, phase: .degrees(300))]),
            size: CGSize(width: 26, height: 26)
        ),
    ]

    /// Geometry helpers for the built-in forms.
    enum FormPath {
        /// A deformed circle: r(θ) = 1 + Σ amount·cos(lobes·θ + phase).
        /// Each harmonic bends the circle in a direction or adds a wobble;
        /// stacks of them read as uneven, hand-drawn circles.
        static func blob(_ harmonics: [(lobes: Int, amount: Double, phase: Angle)]) -> Path {
            var path = Path()
            let steps = 160
            for i in 0 ... steps {
                let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
                var radius: CGFloat = 1
                for harmonic in harmonics {
                    radius += CGFloat(harmonic.amount)
                        * cos(CGFloat(harmonic.lobes) * t + CGFloat(harmonic.phase.radians))
                }
                let p = CGPoint(x: cos(t) * radius, y: sin(t) * radius)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            return path
        }

        /// A corner-rounded regular (or star) polygon in [-1, 1] space.
        /// `radii` cycles per vertex (one value = regular polygon),
        /// `corner` is the rounding fraction toward each neighbour.
        static func polygon(
            sides: Int, radii: [CGFloat] = [1], corner: CGFloat, rotation: Angle
        ) -> Path {
            let rot = CGFloat(rotation.radians)
            var verts: [CGPoint] = []
            for i in 0 ..< sides {
                let t = rot + CGFloat(i) / CGFloat(sides) * 2 * .pi
                let radius = radii[i % radii.count]
                verts.append(CGPoint(x: cos(t) * radius, y: sin(t) * radius))
            }
            var path = Path()
            guard corner > 0 else {
                path.move(to: verts[0])
                verts.dropFirst().forEach { path.addLine(to: $0) }
                path.closeSubpath()
                return path
            }
            var first = true
            for i in 0 ..< sides {
                let previous = verts[(i - 1 + sides) % sides]
                let v = verts[i]
                let next = verts[(i + 1) % sides]
                let a = CGPoint(
                    x: v.x + (previous.x - v.x) * corner,
                    y: v.y + (previous.y - v.y) * corner
                )
                let b = CGPoint(
                    x: v.x + (next.x - v.x) * corner,
                    y: v.y + (next.y - v.y) * corner
                )
                if first {
                    path.move(to: a)
                    first = false
                } else {
                    path.addLine(to: a)
                }
                path.addQuadCurve(to: b, control: v)
            }
            path.closeSubpath()
            return path
        }

        /// A filled parabola bowl: the curve y = x² between its tips, closed
        /// by the straight chord across the top. Built in its final size.
        static func parabola(width: CGFloat, height: CGFloat) -> Path {
            var path = Path()
            let halfWidth = width / 2
            let steps = 64
            for step in 0 ... steps {
                let x = -halfWidth + CGFloat(step) / CGFloat(steps) * width
                let y = -height / 2 + pow(x / halfWidth, 2) * height
                if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(
                    x: x,
                    y: y
                )) }
            }
            path.closeSubpath()
            return path
        }

        /// A true stadium: straight edges, semicircular caps, in final size.
        static func stadium(width: CGFloat, height: CGFloat) -> Path {
            let radius = min(width, height) / 2
            var path = Path()
            path.move(to: CGPoint(x: -width / 2 + radius, y: -height / 2))
            path.addLine(to: CGPoint(x: width / 2 - radius, y: -height / 2))
            path.addArc(
                center: CGPoint(x: width / 2 - radius, y: 0),
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(90),
                clockwise: true
            )
            path.addLine(to: CGPoint(x: -width / 2 + radius, y: height / 2))
            path.addArc(
                center: CGPoint(x: -width / 2 + radius, y: 0),
                radius: radius,
                startAngle: .degrees(90),
                endAngle: .degrees(270),
                clockwise: true
            )
            path.closeSubpath()
            return path
        }

        /// A rounded rectangle centred on the origin, in its final size.
        static func roundedRect(width: CGFloat, height: CGFloat, radius: CGFloat) -> Path {
            Path(
                roundedRect: CGRect(
                    x: -width / 2, y: -height / 2, width: width, height: height
                ),
                cornerRadius: radius
            )
        }

        /// A unit circle sampled densely so resampling keeps it round.
        static func ellipse() -> Path {
            var path = Path()
            let count = 240
            for i in 0 ... count {
                let t = CGFloat(i) / CGFloat(count) * 2 * .pi
                let p = CGPoint(x: cos(t), y: sin(t))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            return path
        }
    }

    // MARK: Pipeline

    /// Reduces any closed outline to the shared sample representation.
    private static func prepare(_ dense: [CGPoint]) -> [CGPoint] {
        let resampled = resample(dense)
        return align(normalize(forceClockwise(resampled)))
    }

    /// Walks path elements, expanding curves into a dense polyline.
    private static func flatten(_ path: Path) -> [CGPoint] {
        let curveSteps = 24
        var outline: [CGPoint] = []
        var current = CGPoint.zero
        var start = CGPoint.zero

        func emitQuadratic(_ control: CGPoint, _ end: CGPoint) {
            let p0 = current
            for step in 1 ... curveSteps {
                let t = Double(step) / Double(curveSteps)
                let m = 1 - t
                let mm = m * m
                let mt = m * t
                let tt = t * t
                let x = mm * p0.x + 2 * mt * control.x + tt * end.x
                let y = mm * p0.y + 2 * mt * control.y + tt * end.y
                outline.append(CGPoint(x: x, y: y))
            }
            current = end
        }

        func emitCubic(_ c1: CGPoint, _ c2: CGPoint, _ end: CGPoint) {
            let p0 = current
            for step in 1 ... curveSteps {
                let t = Double(step) / Double(curveSteps)
                let m = 1 - t
                let mm = m * m
                let mt = m * t
                let tt = t * t
                let x = mm * m * p0.x + 3 * mm * t * c1.x + 3 * mt * t * c2.x + tt * t * end.x
                let y = mm * m * p0.y + 3 * mm * t * c1.y + 3 * mt * t * c2.y + tt * t * end.y
                outline.append(CGPoint(x: x, y: y))
            }
            current = end
        }

        path.cgPath.applyWithBlock { element in
            let element = element.pointee
            switch element.type {
            case .moveToPoint:
                let p = element.points[0]
                if !outline.isEmpty { outline.append(start) }
                current = p
                start = p
                outline.append(p)
            case .addLineToPoint:
                let p = element.points[0]
                outline.append(p)
                current = p
            case .addQuadCurveToPoint:
                emitQuadratic(element.points[0], element.points[1])
            case .addCurveToPoint:
                emitCubic(element.points[0], element.points[1], element.points[2])
            case .closeSubpath:
                if current != start {
                    outline.append(start)
                    current = start
                }
            @unknown default:
                break
            }
        }
        if let first = outline.first, outline.count > 1, outline.last != first {
            outline.append(first)
        }
        return outline
    }

    /// Resamples the polyline to `pointCount` equidistant points by arc length.
    private static func resample(_ dense: [CGPoint]) -> [CGPoint] {
        guard dense.count > 1 else { return dense }

        var segmentLengths: [Double] = []
        segmentLengths.reserveCapacity(dense.count)
        var total: Double = 0
        for i in 0 ..< dense.count {
            let a = dense[i], b = dense[(i + 1) % dense.count]
            let length = hypot(b.x - a.x, b.y - a.y)
            segmentLengths.append(length)
            total += length
        }

        var points: [CGPoint] = []
        points.reserveCapacity(pointCount)
        var walked: Double = 0
        var j = 0
        for i in 0 ..< pointCount {
            let target = Double(i) / Double(pointCount) * total
            while walked + segmentLengths[j] < target && j < dense.count - 1 {
                walked += segmentLengths[j]
                j += 1
            }
            let t = segmentLengths[j] > 0 ? (target - walked) / segmentLengths[j] : 0
            let a = dense[j], b = dense[(j + 1) % dense.count]
            points.append(CGPoint(
                x: a.x + (b.x - a.x) * t,
                y: a.y + (b.y - a.y) * t
            ))
        }
        return points
    }

    /// Centres the geometry on its bounding box and stretches each axis into
    /// [-1, 1], matching the renderer's per-axis mapping. Forms should be
    /// built with the same aspect as their declared `size` so proportions
    /// survive the round trip.
    private static func normalize(_ points: [CGPoint]) -> [CGPoint] {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max(),
              maxX > minX, maxY > minY
        else { return points }
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        return points.map {
            CGPoint(
                x: ($0.x - centerX) / ((maxX - minX) / 2),
                y: ($0.y - centerY) / ((maxY - minY) / 2)
            )
        }
    }

    /// Enforces one winding so all forms traverse in the same direction.
    private static func forceClockwise(_ points: [CGPoint]) -> [CGPoint] {
        var area = 0.0
        for i in 0 ..< points.count {
            let a = points[i], b = points[(i + 1) % points.count]
            area += Double(a.x * b.y - b.x * a.y)
        }
        return area < 0 ? Array(points.reversed()) : points
    }

    /// Rotates the sample order so it starts nearest the positive x axis,
    /// keeping consecutive forms from spinning as they tween.
    private static func align(_ points: [CGPoint]) -> [CGPoint] {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (i, p) in points.enumerated() {
            let d = hypot(p.x - 1, p.y)
            if d < bestDistance {
                bestDistance = d
                best = i
            }
        }
        return Array(points[best...] + points[..<best])
    }
}
