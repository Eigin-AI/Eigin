import SwiftUI

/// The thinking indicator: a near-circle that scales in and morphs through the
/// forms in `MorphForm.all` while breathing, with a line of copy that
/// speaks up as the wait drags on.
///
/// Fully time-derived: the choreography is recomputed from `shownAt` every
/// frame, so the view can be torn down and rebuilt without glitching. One
/// fresh cycle (and copy ladder) per appearance; during stalls the shape
/// keeps running while the copy ladder is parked.
/// A fresh element per appearance: the seed is derived from `shownAt`, so
/// every wait gets its own cycle order, entry pop and copy ladder. The shape
/// morphs continuously through stalls; only the copy ladder is parked, with
/// the clock supplied through `clockStart`/`priorElapsed`.
struct ThinkingIndicator: View {
    /// When this appearance began — anchors the shape cycle, entry and breath.
    let shownAt: Date
    /// When the current thinking stretch began; nil while stalled on the user.
    let clockStart: Date?
    /// Thinking seconds accumulated before the current stretch.
    let priorElapsed: TimeInterval
    /// Whether the turn is currently parked waiting for the user.
    let isStalled: Bool

    @Environment(\.colors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fixed slot hugging the largest form (plus a margin for the spring
    /// overshoot and breath), so the indicator sits flush left with the
    /// assistant text edge.
    private static let slotSize = CGSize(width: 40, height: 40)

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.5 : nil)) { context in
            indicatorAndCopy(at: context.date)
        }
    }

    private func indicatorAndCopy(at date: Date) -> some View {
        // The stage is computed at this level so the swap animation lives
        // on an ancestor — transitions on the view being replaced never see
        // their own removal. The clock pauses during stalls via
        // `clockStart`/`priorElapsed`, so the ladder resumes where it left off.
        let elapsed = (clockStart.map { date.timeIntervalSince($0) } ?? 0) + priorElapsed
        let stage = isStalled ? nil : ThinkingCopy.stage(at: elapsed)
        return HStack(spacing: Spacing.n12) {
            // The chat wait is always thinking, so the wobble runs at full
            // intensity from entry. The blob drives its own timeline.
            MorphBlob(
                shownAt: shownAt,
                intensity: .full,
                color: colors.button.spot.base
            )
            .frame(width: Self.slotSize.width, height: Self.slotSize.height)

            // A single Text morphing between rungs: no structural change, so
            // the label never plays its own transition while the indicator
            // itself scales away — it always exits with the indicator.
            Text(isStalled ? Localized.Chat.Thinking.waitingForYou : stage?.text ?? "")
                .typography(Typography.chatMessage)
                .foregroundStyle(colors.text.standard.muted.opacity(0.6))
                .contentTransition(.interpolate)
        }
        .animation(.easeInOut(duration: 0.4), value: stage)
    }
}

#Preview("Indicator") {
    VStack(spacing: Spacing.n24) {
        ThinkingIndicator(
            shownAt: .now.addingTimeInterval(-6.5),
            clockStart: .now.addingTimeInterval(-6.5),
            priorElapsed: 0,
            isStalled: false
        )
        ThinkingIndicator(
            shownAt: .now.addingTimeInterval(-11),
            clockStart: .now.addingTimeInterval(-11),
            priorElapsed: 0,
            isStalled: false
        )
        ThinkingIndicator(
            shownAt: .now.addingTimeInterval(-45),
            clockStart: .now.addingTimeInterval(-45),
            priorElapsed: 0,
            isStalled: false
        )
    }
    .padding(Spacing.n32)
    .background(Color(white: 0.09))
}

#Preview("Form library") {
    VStack(spacing: Spacing.n32) {
        HStack(spacing: Spacing.n20) {
            ForEach(0 ..< MorphForm.all.count, id: \.self) { i in
                let form = MorphForm.all[i]
                SplineOutline.path(through: form.points.map {
                    CGPoint(x: $0.x * form.size.width / 4, y: $0.y * form.size.height / 4)
                })
                .fill(Color(red: 0.655, green: 0.690, blue: 0.306))
                .frame(width: 21, height: 21)
            }
        }
        ThinkingIndicator(shownAt: .now, clockStart: nil, priorElapsed: 5, isStalled: true)
    }
    .padding(Spacing.n32)
    .background(Color(white: 0.09))
}
