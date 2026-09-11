import Factory
import SwiftData
import SwiftUI

/// The model on the phone, on the same anatomy as every other provider: who
/// it is, the facts, then the one thing to do about it.
///
/// It is the one provider you have to fetch before you can use it, so the
/// asset row sits where another screen lists its models, with the download
/// directly under the thing being downloaded. The header says whether you can
/// use it; the asset row says what the download is doing; neither repeats the
/// other.
struct LocalProviderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Provider.createdAt) private var providers: [Provider]

    let preset: ProviderPreset

    @State private var showInfo = false
    @State private var showDeleteConfirm = false
    @Injected(\.gemmaModelManager) private var gemmaManager: any GemmaModelManaging

    private var localProvider: Provider? {
        providers.first { ProviderPreset.isLocal($0.baseURL) }
    }

    private var isPreparing: Bool {
        switch gemmaManager.state {
        case .downloaded, .preparing:
            true
        default:
            false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Provider.Local.title,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

            AppAnchoredScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    AppIdentityHeader(
                        name: Localized.Provider.Local.title,
                        kind: Localized.Provider.Local.kindLabel,
                        state: connectionState,
                        status: statusLabel,
                        icon: Iconography.Functional.lock
                    )

                    facts

                    // The row carries the live state and its own size, so the
                    // screen says neither: its button is the only place the
                    // decision lives.
                    AssetRow(asset: gemmaManager, showsAction: false)

                    if let action {
                        AppButton(action.label, variant: action.variant) { action.act() }
                    }

                    if gemmaManager.state == .ready {
                        deleteGroup
                    }
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keepScreenAwake(isPreparing)
        .animation(Animations.smooth, value: gemmaManager.state)
        .task {
            if gemmaManager.state == .downloaded {
                await gemmaManager.compile()
            }
        }
        .onChange(of: gemmaManager.state) { _, newState in
            if newState == .downloaded {
                Task { await gemmaManager.compile() }
            }
            if newState == .ready {
                ensureLocalProvider()
            }
        }
        .appSheet(
            isPresented: $showInfo,
            title: Localized.Provider.Local.infoTitle,
            description: Localized.Provider.Local.infoDescription,
            fitsContent: true
        ) {
            LocalModelInfoSheetContent()
        }
    }

    // MARK: - Header state

    private var connectionState: ConnectionState {
        switch gemmaManager.state {
        case .ready:
            .connected
        case .downloading, .downloaded, .preparing, .queued:
            .attention
        case .failed:
            .attention
        case .unavailable:
            .unavailable
        case .notDownloaded:
            .off
        }
    }

    private var statusLabel: String {
        switch gemmaManager.state {
        case .ready: Localized.Provider.Local.Status.ready
        case .notDownloaded: Localized.Provider.Local.Status.notInstalled
        case .queued, .downloading, .downloaded, .preparing:
            Localized.Provider.Local.Status.gettingReady
        case .unavailable: Localized.Provider.Local.Status.notSupported
        case .failed: Localized.Provider.Local.Status.downloadFailed
        }
    }

    // MARK: - Facts

    /// The screen states the facts; the info sheet answers the question
    /// behind them.
    private var facts: some View {
        AppRowsGroup(
            rows: [
                AppRowSpec(
                    title: Localized.Model.Facts.goodFor,
                    value: Localized.Model.Facts.goodForValue,
                    accessory: .none
                ),
                AppRowSpec(
                    title: Localized.Model.Facts.limitations,
                    value: Localized.Model.Facts.limitationsValue,
                    accessory: .none
                ),
                AppRowSpec(
                    title: Localized.Provider.Relay.Facts.howItWorks,
                    tone: .muted,
                    action: { showInfo = true }
                ),
            ]
        )
    }

    // MARK: - Action

    /// One button carries the whole decision: get it, or stop getting it.
    private struct Action {
        let label: String
        let variant: AppButtonVariant
        let act: () -> Void
    }

    private var action: Action? {
        switch gemmaManager.state {
        case .notDownloaded:
            Action(label: Localized.Common.Actions.download, variant: .primary) {
                Haptics.light()
                Task { await gemmaManager.download() }
            }
        case .failed:
            Action(label: Localized.Common.Actions.retry, variant: .primary) {
                Task { await gemmaManager.download() }
            }
        case .queued, .downloading, .downloaded, .preparing:
            Action(label: Localized.Provider.Local.cancelDownload, variant: .secondary) {
                gemmaManager.cancel()
            }
        case .ready, .unavailable:
            nil
        }
    }

    private var deleteGroup: some View {
        AppRowsGroup(
            rows: [
                AppRowSpec(
                    title: Localized.Provider.Local.deleteModel,
                    accessory: .trash,
                    tone: .destructive,
                    action: { showDeleteConfirm = true }
                ),
            ]
        )
        .confirmationDialog(
            Localized.Provider.Local.deleteModel,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(Localized.Common.Actions.delete, role: .destructive) {
                deleteModel()
            }
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
        } message: {
            Text(Localized.Model.removeWarning)
        }
    }

    // MARK: - Provider plumbing

    private func ensureLocalProvider() {
        guard localProvider == nil else { return }
        let provider = Provider(name: preset.name, baseURL: preset.baseURL)
        provider.availableModels = ["gemma-4-e2b"]
        provider.enabledModels = ["gemma-4-e2b"]
        modelContext.insert(provider)
        Haptics.success()
    }

    private func deleteModel() {
        gemmaManager.delete()
        if let provider = localProvider {
            modelContext.delete(provider)
        }
        Haptics.success()
    }
}

#Preview {
    let preset = ProviderPreset.all.first { ProviderPreset.isLocal($0.baseURL) }!
    return NavigationStack {
        LocalProviderView(preset: preset)
    }
    .previewEnvironment()
}
