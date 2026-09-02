import SwiftData
import SwiftUI

/// Manages the on-device Gemma model: download, preparation, and deletion.
///
/// Built around the shared ``AssetRow`` with a minimal metadata block — what
/// the model is, how big it is, that it runs on device — and state-appropriate
/// primary actions. The row carries the live status; this screen carries the
/// decisions.
struct LocalProviderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Query(sort: \Provider.createdAt) private var providers: [Provider]

    let preset: ProviderPreset

    @State private var showDeleteConfirm = false
    @Bindable private var gemmaManager = GemmaModelManager.shared

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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Provider.Picker.onDeviceModel,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

            VStack(spacing: Spacing.n32) {
                VStack(alignment: .leading, spacing: Spacing.n16) {
                    // Status first, then the facts, then the prose. The
                    // action lives in the button below, so the row omits its
                    // own control.
                    AssetRow(asset: gemmaManager, showsAction: false)

                    metadataFacts

                    Text(gemmaManager.downloadDescription)
                        .typography(Typography.description)
                        .foregroundStyle(colors.text.standard.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                actions
            }
            .padding(.horizontal, Spacing.n24)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        }
        .frame(maxWidth: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keepScreenAwake(isPreparing)
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
    }

    // MARK: - Metadata

    /// What you can't read off the title, the row, or the description: what
    /// to expect from it, what not to, and what it costs in storage.
    private var metadataFacts: some View {
        AppCardSurface(padding: 0) {
            VStack(spacing: 0) {
                factRow(
                    Localized.Model.Facts.goodFor,
                    value: Localized.Model.Facts.goodForValue,
                    divider: true
                )
                factRow(
                    Localized.Model.Facts.limitations,
                    value: Localized.Model.Facts.limitationsValue,
                    divider: true
                )
                factRow(
                    Localized.Model.Facts.sizeOnDevice,
                    value: gemmaManager.sizeDescription ?? ""
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func factRow(_ label: String, value: String, divider: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.n16) {
                Text(label)
                    .typography(Typography.description)
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.text.standard.base)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                Text(value)
                    .typography(Typography.description)
                    .foregroundStyle(colors.text.standard.muted)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.n20)
            .padding(.vertical, Spacing.n16)
            .contentShape(Rectangle())

            if divider {
                Divider().padding(.leading, Spacing.n20)
            }
        }
    }

    // MARK: - Actions

    /// One full-width button that carries the screen's whole decision:
    /// download it, stop it, or remove it.
    @ViewBuilder
    private var actions: some View {
        switch gemmaManager.state {
        case .notDownloaded:
            AppButton(Localized.Common.Actions.download) {
                Haptics.light()
                Task { await gemmaManager.download() }
            }

        case .failed:
            AppButton(Localized.Common.Actions.retry) {
                Task { await gemmaManager.download() }
            }

        case .queued, .downloading:
            AppButton(Localized.LocalModel.cancel, variant: .secondary) {
                gemmaManager.cancel()
            }

        case .ready:
            AppButton(Localized.LocalModel.delete, variant: .secondary) {
                showDeleteConfirm = true
            }
            .confirmationDialog(
                Localized.LocalModel.delete,
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

        case .downloaded, .preparing, .unavailable:
            EmptyView()
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
