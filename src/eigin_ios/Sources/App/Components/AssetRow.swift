import SwiftUI

/// The shared row for any downloadable on-device asset.
///
/// One atom, all states: progress circle · name · one meta line of facts ·
/// one trailing control. Numbers, not spinners — downloading shows percent
/// and a time-left estimate once a stable rate exists. Warnings (storage,
/// unsupported device) are informational: the reason is the copy, and there
/// is deliberately no action in the row.
struct AssetRow: View {
    let asset: any OnDemandAsset
    /// Optional explainer shown above the row (what this asset is, why it's offered).
    var secondaryText: String?
    /// Delete affordance for installed rows. Local-assets management uses
    /// this; surfaces that shouldn't offer deletion leave it nil.
    var onDelete: (() -> Void)?
    /// Set false where the screen owns the action itself (a primary button
    /// below), so the same affordance isn't offered twice.
    var showsAction = true

    @Environment(\.colors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n8) {
            if let secondaryText {
                Text(secondaryText)
                    .typography(Typography.note)
                    .foregroundStyle(colors.text.standard.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            row
        }
    }

    private var row: some View {
        HStack(spacing: Spacing.n16) {
            glyph
                .frame(width: Metrics.glyph, height: Metrics.glyph)

            VStack(alignment: .leading, spacing: Spacing.n4) {
                Text(asset.displayName)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)

                meta
                    .typography(Typography.note)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            if showsAction {
                trailingControl
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
        .background(colors.surface.standard.alternative)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .animation(Animations.snap, value: stateKey)
    }

    // MARK: - Meta line

    @ViewBuilder
    private var meta: some View {
        switch asset.state {
        case .notDownloaded:
            metaParts(localized: Localized.Asset.notInstalled, plain: asset.sizeDescription)
                .foregroundStyle(colors.text.standard.muted)

        case .queued:
            Text(Localized.Asset.queued)
                .foregroundStyle(colors.text.standard.muted)

        case .downloading(let info):
            metaTransfer(info)
                .foregroundStyle(colors.text.standard.muted)

        case .downloaded:
            metaParts(localized: Localized.Asset.installed, plain: asset.sizeDescription)
                .foregroundStyle(colors.text.standard.muted)

        case .preparing(let fraction):
            if let fraction {
                Text(verbatim: "\(Int(fraction * 100))%")
                    .foregroundStyle(colors.text.standard.muted)
            } else {
                Text(Localized.Asset.preparing)
                    .foregroundStyle(colors.text.standard.muted)
            }

        case .ready:
            Text(Localized.Asset.readyToUse)
                .foregroundStyle(colors.text.standard.muted)

        case .failed(let message):
            Text(message)
                .foregroundStyle(colors.text.standard.error)
                .lineLimit(3)

        case .unavailable(let reason):
            Text(reason)
                .foregroundStyle(colors.icon.signal.notice)
                .lineLimit(4)
        }
    }

    /// "% · time left" — percent plus coarse localised time units only:
    /// seconds under a minute, then minutes, then hours. Never "5 000 s
    /// left", never bytes.
    private func metaTransfer(_ info: AssetTransferInfo) -> some View {
        metaParts(
            plain: "\(Int((info.fractionCompleted * 100).rounded()))%",
            plain2: Self.timeLeftText(info.estimatedSecondsLeft)
        )
    }

    private func metaParts(localized: String, plain: String?) -> some View {
        metaParts(
            plain: [localized, plain].compactMap(\.self).joined(separator: " · "),
            plain2: nil
        )
    }

    @ViewBuilder
    private func metaParts(plain: String, plain2: String?) -> some View {
        if let plain2, !plain2.isEmpty {
            HStack(spacing: 0) {
                Text(verbatim: plain)
                Text(verbatim: " · \(plain2)")
            }
            .monospacedDigit()
        } else {
            Text(verbatim: plain).monospacedDigit()
        }
    }

    // MARK: - Glyph

    /// One circle that IS the progress, layered so every state is the same
    /// shape changing rather than a swap: the track is always there, the
    /// accent arc grows with the transfer, and the fill closes it when ready.
    private var glyph: some View {
        ZStack {
            Circle()
                .stroke(colors.border.standard.base, lineWidth: Metrics.ringStroke)
                .opacity(showsRing ? 1 : 0)

            Circle()
                .trim(from: 0, to: arcFraction)
                .stroke(colors.accent, style: StrokeStyle(
                    lineWidth: Metrics.ringStroke,
                    lineCap: .round
                ))
                .rotationEffect(.degrees(-90))
                .opacity(showsArc ? 1 : 0)

            if sweeps {
                sweepArc
                    .transition(.opacity)
            }

            // The fill grows out of the completed ring. Ready is approve
            // green: the one settled state, distinct from the neutral track.
            Circle()
                .fill(colors.icon.signal.approve)
                .opacity(isReady ? 1 : 0)
                .scaleEffect(isReady ? 1 : 0.1)

            Circle()
                .stroke(signalTint ?? .clear, lineWidth: Metrics.ringStroke)
                .opacity(signalTint == nil ? 0 : 1)
        }
        .frame(width: Metrics.ringDiameter, height: Metrics.ringDiameter)
        .animation(.linear(duration: 0.3), value: arcFraction)
        .animation(Animations.snap, value: stateKey)
    }

    /// A short accent arc drifting around the ring — waiting, not stuck.
    /// Fixed length and rotated, because `trim(from:to:)` clamps at 1.0 and
    /// visibly shortens the arc as it crosses the seam.
    private var sweepArc: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Metrics.sweepPeriod) / Metrics.sweepPeriod
            Circle()
                .trim(from: 0, to: Metrics.sweepArcFraction)
                .stroke(colors.accent, style: StrokeStyle(
                    lineWidth: Metrics.ringStroke,
                    lineCap: .round
                ))
                .rotationEffect(.degrees(t * 360))
        }
    }

    /// Identity of the current state, so state changes snap while progress
    /// within a state stays linear.
    private var stateKey: String {
        switch asset.state {
        case .notDownloaded: "offer"
        case .queued: "queued"
        case .downloading: "downloading"
        case .downloaded, .preparing: "preparing"
        case .ready: "ready"
        case .failed: "failed"
        case .unavailable: "unavailable"
        }
    }

    /// How far round the accent arc runs. A hair of arc from the first byte,
    /// so the transfer reads as started.
    private var arcFraction: Double {
        switch asset.state {
        case .downloading(let info): max(0.03, min(1, info.fractionCompleted))
        case .downloaded, .preparing, .ready: 1
        default: 0
        }
    }

    /// Ready is excluded: the finished circle is a plain neutral fill, not an
    /// accent ring around it.
    private var showsArc: Bool {
        switch asset.state {
        case .downloading, .downloaded, .preparing: true
        default: false
        }
    }

    private var showsRing: Bool {
        // Ready is a finished disc: the track has no longer anything to say.
        !isReady && signalTint == nil
    }

    /// Queued and fractionless preparing both drift: neither can be measured.
    private var sweeps: Bool {
        switch asset.state {
        case .queued, .downloaded: true
        case .preparing(let fraction): fraction == nil
        default: false
        }
    }

    private var isReady: Bool {
        asset.state == .ready
    }

    /// Non-nil only for the informational states, which tint the ring rather
    /// than adding anything to it.
    private var signalTint: Color? {
        switch asset.state {
        case .failed: colors.icon.signal.negative
        case .unavailable: colors.icon.signal.notice
        default: nil
        }
    }

    // MARK: - Trailing control

    /// What the button is right now. One element across states, so the colour
    /// morphs and only the icon swaps.
    private struct ControlSpec {
        let key: String
        let background: Color
        let icon: Image
        let tint: Color
        let action: () -> Void
    }

    /// Always a same-size action button; the colour and icon carry the state:
    /// accent arrow (download) → neutral x (cancel) → neutral trash (delete).
    /// Nil where the row has nothing to offer.
    private var controlSpec: ControlSpec? {
        switch asset.state {
        case .notDownloaded, .failed:
            ControlSpec(
                key: "download",
                background: colors.accent,
                icon: Iconography.Functional.Arrow.down,
                tint: colors.text.button.onSpot
            ) {
                Haptics.light()
                Task { await asset.download() }
            }

        case .queued, .downloading:
            ControlSpec(
                key: "cancel",
                background: colors.button.navigation.base,
                icon: Iconography.Functional.x,
                tint: colors.icon.standard.base
            ) {
                asset.delete()
            }

        case .ready:
            onDelete.map { delete in
                ControlSpec(
                    key: "delete",
                    background: colors.button.navigation.base,
                    // Red stays on the glyph, never the whole control.
                    icon: Iconography.Functional.trash,
                    tint: colors.text.standard.error,
                    action: delete
                )
            }

        case .downloaded, .preparing, .unavailable:
            nil
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if let spec = controlSpec {
            Button(action: spec.action) {
                ZStack {
                    Circle().fill(spec.background)
                    spec.icon
                        .renderingMode(.template)
                        .fit(size: Metrics.controlIcon)
                        .foregroundStyle(spec.tint)
                        .id(spec.key)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: Metrics.glyph, height: Metrics.glyph)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Time formatting

    /// Human time-left, as short as possible: "42 s left", "12 min left",
    /// "1 h 5 min left". Rounded up so it never shows a confident-looking 0.
    static func timeLeftText(_ seconds: Double?) -> String? {
        guard let seconds, seconds >= 1 else { return nil }
        let value = if seconds < 60 {
            Localized.Asset.durationSeconds(String(Int(seconds.rounded(.up))))
        } else if seconds < 3600 {
            Localized.Asset.durationMinutes(String(Int((seconds / 60).rounded(.up))))
        } else {
            Localized.Asset.durationHours(
                String(Int(seconds / 3600)),
                String(Int((seconds.truncatingRemainder(dividingBy: 3600) / 60).rounded(.up)))
            )
        }
        return Localized.Asset.timeLeft(value)
    }
}

// MARK: - Metrics

private extension Image {
    /// Sized template rendering.
    func fit(size: CGFloat) -> some View {
        resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

private enum Metrics {
    static let glyph: CGFloat = 34
    /// Visible ring diameter shared by every circular glyph, so states read
    /// as the same size.
    static let ringDiameter: CGFloat = 26
    static let ringStroke: CGFloat = 4
    /// Icon inside the trailing control; the circle stays 34pt.
    static let controlIcon: CGFloat = 17
    /// Queued sweep cadence.
    static let sweepPeriod: Double = 1.6
    static let sweepArcFraction: Double = 0.18
}

// MARK: - Previews

#Preview("AssetRow states") {
    VStack(spacing: Spacing.n16) {
        AssetRow(asset: FakeAsset(state: .notDownloaded))
        AssetRow(asset: FakeAsset(state: .queued))
        AssetRow(asset: FakeAsset(state: .downloading(AssetTransferInfo(
            fractionCompleted: 0.62,
            bytesCompleted: 1_600_000_000,
            totalBytes: 2_583_691_264,
            estimatedSecondsLeft: 42
        ))))
        AssetRow(asset: FakeAsset(state: .downloading(AssetTransferInfo(
            fractionCompleted: 0.02,
            bytesCompleted: 50_000_000,
            totalBytes: 2_583_691_264,
            estimatedSecondsLeft: nil
        ))))
        AssetRow(
            asset: FakeAsset(state: .preparing(fractionCompleted: nil)),
            secondaryText: "High-quality voice, entirely on device."
        )
        AssetRow(asset: FakeAsset(state: .ready))
        AssetRow(asset: FakeAsset(state: .failed("Network connection lost.")))
        AssetRow(asset: FakeAsset(state: .unavailable("You need at least 5.2 GB of free storage.")))
        AssetRow(asset: FakeAsset(state: .ready), onDelete: {})
    }
    .padding(Spacing.n24)
    .previewEnvironment()
}

private final class FakeAsset: OnDemandAsset, @unchecked Sendable {
    let id = "fake"
    let displayName = "Gemma 4 E2B"
    let downloadDescription = "On-device assistant model"
    let sizeDescription: String? = "~2.6 GB"
    var state: AssetState
    var hasBeenDeclined = false

    init(state: AssetState) {
        self.state = state
    }

    func download() async {}
    func delete() {}
    func decline() {}
}
