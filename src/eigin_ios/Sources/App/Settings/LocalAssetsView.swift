import Factory
import SwiftUI

/// The single surface for managing every downloadable on-device asset:
/// the local model and the voice engine models, each as one ``AssetRow``.
///
/// Download, retry, and cancel are handled by the rows themselves; installed
/// rows get a row-level delete with confirmation. Nothing here scans stale
/// caches — that stays with the debug Model Storage screen.
struct LocalAssetsView: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [any OnDemandAsset] = []
    @State private var deleteCandidate: AssetItem?

    private var installedCount: Int {
        // Only states backed by bytes on disk; failed/unavailable/in-flight
        // rows are not installed.
        assets.count { state in
            switch state.state {
            case .ready, .downloaded, .preparing:
                true
            default:
                false
            }
        }
    }

    var body: some View {
        SoftEdgeScrollView {
            // Label and card are one group, like every other settings
            // screen; the wider page gap sits between sections.
            VStack(alignment: .leading, spacing: Sizing.PageLayout.ContentGrouping.gap) {
                Text(Localized.Settings.LocalAssets.totalInstalled(String(installedCount)))
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
                    .padding(.horizontal, Spacing.n8)

                AppCardSurface(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                            if index > 0 {
                                Divider()
                            }
                            AssetRow(asset: asset, onDelete: {
                                deleteCandidate = AssetItem(asset)
                            })
                            .padding(.vertical, Spacing.n2)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        } header: {
            AppNavigationHeader(
                title: Localized.Settings.LocalAssets.title,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            assets = Container.shared.localAssets()
            prepareAssets()
        }
        .confirmationDialog(
            Localized.Common.Actions.delete,
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteCandidate.map(\.asset)
        ) { asset in
            Button(Localized.Common.Actions.delete, role: .destructive) {
                asset.delete()
            }
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
        } message: { _ in
            Text(Localized.Model.removeWarning)
        }
    }

    /// Kick off any post-download preparation so an asset never sits in a
    /// busy state just because this screen was opened.
    private func prepareAssets() {
        for asset in assets {
            asset.prepareIfNeeded()
        }
    }
}

#Preview {
    NavigationStack {
        LocalAssetsView()
    }
    .previewEnvironment()
}
