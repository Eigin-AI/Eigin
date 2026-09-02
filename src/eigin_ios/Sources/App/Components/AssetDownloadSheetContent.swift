import SwiftUI

/// A reusable prompt offering the user an on-demand asset download.
///
/// Present as sheet content with ``.appSheet`` so the header, description,
/// and dismiss button are handled by the design system — pass the asset's
/// `downloadDescription` as the sheet's `description:` and leave the dismiss
/// button on (dismissing a pre-call download falls back to system voice).
/// The content is one ``AssetRow`` plus the opt-out: offer → download → ready,
/// with the auto-accept firing on ready.
struct AssetDownloadSheetContent: View {
    let asset: any OnDemandAsset
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.colors) private var colors

    private var isBusy: Bool {
        switch asset.state {
        case .queued, .downloading, .preparing, .downloaded:
            true
        default:
            false
        }
    }

    var body: some View {
        VStack(spacing: Spacing.n32) {
            AssetRow(asset: asset)

            actions
        }
        .padding(.horizontal, Sizing.PageLayout.ContentGrouping.Px.mobile)
        .keepScreenAwake(isBusy)
        .onChange(of: asset.state) {
            if asset.state == .ready {
                onAccept()
            }
        }
    }

    // MARK: - Actions

    /// One button always, so the sheet never resizes mid-download.
    @ViewBuilder
    private var actions: some View {
        switch asset.state {
        // The row's trailing control starts the download — this prompt only
        // offers the opt-out.
        case .notDownloaded:
            AppButton(Localized.Common.Actions.notNow, variant: .secondary) {
                asset.decline()
                onDecline()
            }

        case .queued, .downloading, .downloaded, .preparing:
            // Leaves the download running: this call falls back, and the
            // asset switches on by itself once it's ready.
            AppButton(Localized.Asset.useWhenReady, variant: .secondary) {
                onDecline()
            }

        case .failed:
            AppButton(Localized.Common.Actions.retry) {
                Task { await asset.download() }
            }

        case .ready:
            AppButton(Localized.Common.Actions.continue) {
                onAccept()
            }

        case .unavailable:
            AppButton(Localized.Common.Actions.notNow, variant: .secondary) {
                onDecline()
            }
        }
    }
}

// MARK: - Previews

#Preview("Not Downloaded") {
    fakeSheet(state: .notDownloaded)
}

#Preview("Downloading – 62%") {
    fakeSheet(state: .downloading(AssetTransferInfo(
        fractionCompleted: 0.62,
        bytesCompleted: 62_000_000,
        totalBytes: 100_000_000,
        estimatedSecondsLeft: 38
    )))
}

#Preview("Ready") {
    fakeSheet(state: .ready)
}

#Preview("Failed") {
    fakeSheet(state: .failed("Network connection lost. Please try again."))
}

#Preview("Unavailable") {
    fakeSheet(
        state: .unavailable("You need at least 5.2 GB of free storage to download the model.")
    )
}

@MainActor
private func fakeSheet(state: AssetState) -> some View {
    AssetDownloadSheetContent(
        asset: FakeOnDemandAsset(state: state),
        onAccept: {},
        onDecline: {}
    )
    .previewEnvironment()
}

// MARK: - FakeOnDemandAsset

@MainActor
private final class FakeOnDemandAsset: OnDemandAsset, @unchecked Sendable {
    let id = "fake"
    let displayName = "Enhanced Voice"
    let downloadDescription = "High-quality voice model that runs entirely on your device."
    let sizeDescription: String? = "~100 MB"
    var state: AssetState
    var hasBeenDeclined = false

    init(state: AssetState) {
        self.state = state
    }

    func download() async {}
    func delete() {}
    func decline() {}
}
