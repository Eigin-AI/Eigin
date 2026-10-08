import SwiftUI

/// The agent hatching. The green circle with the mark starts working like the
/// thinking indicator, breathing harder each time and squeezing the mark as it
/// contracts. Through the last, droplets fall in from off screen and it
/// swallows them. That squeeze takes the mark away; the blob snaps back to a
/// circle, splashing, and the agent's face springs into it.
///
/// Drawn from ``HatchTimeline`` on one clock, so it plays the same as the
/// design gallery. Its canvas spills well past `size`; the screen clips it.
/// Each moment is drawn by ``AgentHatchFrame``.
struct AgentHatch: View {
    let emoji: String
    var size: CGFloat = 140
    /// Time multiplier, so the moment can be watched in slow motion.
    var speed: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    /// Settled for good: the clock stops asking for frames.
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || finished)) { context in
            let t = reduceMotion
                ? HatchTimeline.settled
                : min(context.date.timeIntervalSince(start) * speed, HatchTimeline.settled)
            AgentHatchFrame(emoji: emoji, size: size, t: t)
        }
        .frame(width: size, height: size)
        .task {
            await tapAlong()
            let rest = HatchTimeline.settled / speed - Date.now.timeIntervalSince(start)
            if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
            finished = true
        }
        .accessibilityHidden(true)
    }

    /// A soft tap as each squeeze lands and a firm one on the release, timed
    /// to the same clock as the drawing.
    private func tapAlong() async {
        guard !reduceMotion else { return }
        let squeezes = [HatchTimeline.breaths[2].at, HatchTimeline.breaths[4].at]
        let moments = squeezes.map { ($0, false) } + [(HatchTimeline.release, true)]
        for (at, isRelease) in moments {
            let wait = at / speed - Date.now.timeIntervalSince(start)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            isRelease ? Haptics.medium() : Haptics.light()
        }
    }
}

/// One moment of the hatch, `t` seconds in.
struct AgentHatchFrame: View {
    let emoji: String
    let size: CGFloat
    let t: TimeInterval

    @Environment(\.colors) private var colors

    private var vessel: Double {
        size * 0.89
    }

    private var radius: Double {
        vessel / 2
    }

    private var markSize: Double {
        vessel * 40 / 56
    }

    /// Reaches past the vessel and off any phone screen, for the droplets to
    /// fall in from and the burst to spread into.
    private var canvas: Double {
        size * 8
    }

    var body: some View {
        let entry = HatchTimeline.arrival(t)
        let face = HatchTimeline.face(t)
        let mark = HatchTimeline.mark(t)
        return ZStack {
            Canvas { context, area in
                draw(at: t, in: &context, centre: CGPoint(x: area.width / 2, y: area.height / 2))
            }
            .frame(width: canvas, height: canvas)
            .allowsHitTesting(false)

            // Always there, unseen until the release, so the glyph is drawn
            // before its moment. Sized by font rather than scaled, to stay sharp.
            Text(emoji)
                .font(.system(size: max(1, markSize * 0.85 * face.scale)))
                .opacity(face.opacity)
                .rotationEffect(.degrees(face.rotate))

            if !HatchTimeline.released(t) {
                Iconography.Brand.avatar
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(colors.text.standard.base)
                    .frame(width: markSize, height: markSize)
                    .scaleEffect(mark.scale)
                    .rotationEffect(.degrees(mark.rotate))
                    .offset(x: mark.x * radius, y: mark.y * radius)
            }
        }
        .frame(width: size, height: size)
        .opacity(entry.opacity)
        .scaleEffect(entry.scale)
    }

    private func draw(at t: TimeInterval, in context: inout GraphicsContext, centre: CGPoint) {
        let brand = colors.surface.impact.base
        let place = CGAffineTransform(translationX: centre.x, y: centre.y)

        for ring in HatchTimeline.ripples(t, radius: radius) {
            context.stroke(
                SplineOutline.path(through: ring.points).applying(place),
                with: .color(brand.opacity(ring.opacity)),
                lineWidth: ring.width
            )
        }

        let droplets = HatchDroplets.gathering(t, radius: radius, reach: canvas / 2)
            + HatchDroplets.splash(t, radius: radius)
        for drop in droplets {
            let shape = Path(ellipseIn: CGRect(
                x: -drop.long,
                y: -drop.wide,
                width: drop.long * 2,
                height: drop.wide * 2
            ))
            .applying(CGAffineTransform(rotationAngle: drop.angle)
                .concatenating(CGAffineTransform(translationX: drop.centre.x, y: drop.centre.y))
                .concatenating(place))
            let tint = colors.text.standard.muted.mix(with: brand, by: drop.tint)
            context.fill(shape, with: .color(tint.opacity(drop.opacity)))
        }

        // Once the agent has a face, the circle softens to a neutral surface.
        let softened = HatchTimeline
            .easeOut(HatchTimeline.clamp((t - HatchTimeline.release) / 0.25))
        let fill = brand.mix(with: colors.surface.standard.elevated, by: softened)
        let outline = HatchTimeline
            .blob(t, radius: radius) { HatchDroplets.swallowing(t, angle: $0) }
        context.fill(SplineOutline.path(through: outline).applying(place), with: .color(fill))
    }
}

#Preview {
    AgentHatch(emoji: "🛰️")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.92))
        .resolveTheme()
}
