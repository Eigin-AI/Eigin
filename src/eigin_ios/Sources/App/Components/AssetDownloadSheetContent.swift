import SwiftUI

/// A reusable prompt offering the user an on-demand asset download.
///
/// Present as sheet content with ``.appSheet`` so the header, background,
/// and chrome are handled by the design system. The view only renders the
/// inner state-based experience: offer → download with progress → completion.
struct AssetDownloadSheetContent: View {
    let asset: any OnDemandAsset
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.colors) private var colors

    private var isInProgress: Bool {
        switch asset.state {
        case .downloading, .downloaded, .compiling:
            true
        default:
            false
        }
    }

    var body: some View {
        VStack(spacing: Spacing.n32) {
            Spacer()

            stateContent

            Spacer()

            actions
        }
        .padding(.horizontal, Sizing.PageLayout.ContentGrouping.Px.mobile)
        .keepScreenAwake(isInProgress)
        .onChange(of: asset.state) {
            if asset.state == .ready {
                onAccept()
            }
        }
    }

    // MARK: - State Content

    @ViewBuilder
    private var stateContent: some View {
        switch asset.state {
        case .notDownloaded:
            notDownloadedView

        case .downloading(let progress):
            downloadingView(progress: progress)

        case .downloaded, .compiling:
            compilingView

        case .ready:
            readyView

        case .failed(let message):
            failedView(message: message)
        }
    }

    // MARK: - Not Downloaded

    private var notDownloadedView: some View {
        VStack(spacing: Spacing.n32) {
            Image(systemName: "waveform")
                .font(Typography.titleXl.font)
                .foregroundStyle(colors.accent)

            Text(Localized.Voice.downloadPitch)
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.muted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Downloading

    private func downloadingView(progress: Double) -> some View {
        VStack(spacing: Spacing.n32) {
            ZStack {
                CircularProgressView(
                    progress: progress,
                    size: 150,
                    lineWidth: 8,
                    accentColor: colors.accent
                )

                Text(verbatim: "\(Int(progress * 100))%")
                    .typography(Typography.titleM)
                    .foregroundStyle(colors.text.standard.base)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Text(Localized.Status.downloading)
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.muted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Compiling

    private var compilingView: some View {
        VStack(spacing: Spacing.n32) {
            Image(systemName: "rectangle.3.group")
                .font(Typography.titleXl.font)
                .foregroundStyle(colors.accent)
                .symbolEffect(.breathe, options: .repeating)

            Text(Localized.Status.preparing)
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.muted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Ready

    private var readyView: some View {
        VStack(spacing: Spacing.n32) {
            Image(systemName: "checkmark.circle.fill")
                .font(Typography.titleXl.font)
                .foregroundStyle(colors.accent)

            Text(Localized.Status.ready)
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.muted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: Spacing.n32) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Typography.titleXl.font)
                .foregroundStyle(colors.text.standard.error)

            VStack(spacing: Spacing.n8) {
                Text(Localized.LocalModel.downloadFailed)
                    .typography(Typography.titleM)
                    .foregroundStyle(colors.text.standard.base)

                Text(message)
                    .typography(Typography.body)
                    .foregroundStyle(colors.text.standard.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        switch asset.state {
        case .notDownloaded, .failed:
            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(Localized.Common.Actions.download) {
                    Task { await asset.download() }
                }

                AppButton(Localized.Common.Actions.notNow, variant: .secondary) {
                    asset.decline()
                    onDecline()
                }
            }

        case .downloading, .downloaded, .compiling:
            EmptyView()

        case .ready:
            AppButton(Localized.Common.Actions.continue) {
                onAccept()
            }
        }
    }
}

// MARK: - Previews

#Preview("Not Downloaded") {
    AssetDownloadSheetContent(
        asset: FakeOnDemandAsset(state: .notDownloaded),
        onAccept: {},
        onDecline: {}
    )
    .previewEnvironment()
}

#Preview("Downloading – 35%") {
    AssetDownloadSheetContent(
        asset: FakeOnDemandAsset(state: .downloading(fractionCompleted: 0.35)),
        onAccept: {},
        onDecline: {}
    )
    .previewEnvironment()
}

#Preview("Compiling") {
    AssetDownloadSheetContent(
        asset: FakeOnDemandAsset(state: .compiling(fractionCompleted: 0)),
        onAccept: {},
        onDecline: {}
    )
    .previewEnvironment()
}

#Preview("Ready") {
    AssetDownloadSheetContent(
        asset: FakeOnDemandAsset(state: .ready),
        onAccept: {},
        onDecline: {}
    )
    .previewEnvironment()
}

#Preview("Failed") {
    AssetDownloadSheetContent(
        asset: FakeOnDemandAsset(state: .failed("Network connection lost. Please try again.")),
        onAccept: {},
        onDecline: {}
    )
    .previewEnvironment()
}

// MARK: - FakeOnDemandAsset

private final class FakeOnDemandAsset: OnDemandAsset {
    let id = "fake"
    let displayName = "Enhanced Voice"
    let downloadDescription = "High-quality voice model (~300 MB)"
    var state: AssetState
    var hasBeenDeclined = false

    init(state: AssetState) {
        self.state = state
    }

    func download() async {}
    func delete() {}
    func decline() {}
}
