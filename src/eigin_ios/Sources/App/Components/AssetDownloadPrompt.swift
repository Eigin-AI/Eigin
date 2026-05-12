import SwiftUI

/// A reusable prompt offering the user an on-demand asset download.
///
/// Present as a sheet or popover when a better capability is available
/// but the required model isn't downloaded yet. Handles the full flow:
/// offer → download with progress → completion.
struct AssetDownloadPrompt: View {
    let asset: any OnDemandAsset
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.colors) private var colors

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            icon
            text

            Spacer()

            actions
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
        .onChange(of: asset.state) {
            if asset.state == .ready {
                onAccept()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var icon: some View {
        switch asset.state {
        case .downloading:
            ProgressView()
                .controlSize(.large)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
        default:
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(colors.accent)
        }
    }

    private var text: some View {
        VStack(spacing: Spacing.sm) {
            Text(asset.displayName)
                .typography(Typography.largeTitle)
                .foregroundStyle(colors.textPrimary)

            switch asset.state {
            case .notDownloaded:
                Text(asset.downloadDescription)
                    .typography(Typography.callout)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
            case .downloading(let progress):
                ProgressView(value: progress)
                    .padding(.horizontal, Spacing.md)
                Text(Localized.Status.downloading)
                    .typography(Typography.caption)
                    .foregroundStyle(colors.textSecondary)
            case .downloaded, .compiling:
                ProgressView()
                    .controlSize(.small)
                Text(Localized.Status.preparing)
                    .typography(Typography.caption)
                    .foregroundStyle(colors.textSecondary)
            case .ready:
                Text(Localized.Status.ready)
                    .typography(Typography.callout)
                    .foregroundStyle(colors.textSecondary)
            case .failed(let message):
                Text(message)
                    .typography(Typography.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Spacing.md) {
            switch asset.state {
            case .notDownloaded, .failed:
                Button {
                    Task { await asset.download() }
                } label: {
                    Text(Localized.Common.Actions.download)
                        .typography(Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)

                Button {
                    asset.decline()
                    onDecline()
                } label: {
                    Text(Localized.Common.Actions.notNow)
                        .typography(Typography.callout)
                        .foregroundStyle(colors.textSecondary)
                }
            case .downloading, .downloaded, .compiling:
                EmptyView()
            case .ready:
                Button {
                    onAccept()
                } label: {
                    Text(Localized.Common.Actions.continue)
                        .typography(Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
            }
        }
    }
}
