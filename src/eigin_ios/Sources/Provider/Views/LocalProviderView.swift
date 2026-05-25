import SwiftData
import SwiftUI

/// Manages the on-device Gemma model: download, preparation, and deletion.
///
/// Mirrors the state-based UI used in onboarding, plus a manage state when the
/// model is ready that lets the user delete the downloaded weights.
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
        gemmaManager.state == .downloaded || gemmaManager.state.isCompiling
    }

    var body: some View {
        VStack(spacing: Spacing.n32) {
            Spacer()
            stateContent
            Spacer()
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.bottom, Spacing.n32)
        .frame(maxWidth: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle(Localized.Provider.Picker.onDeviceModel, style: Typography.titleXl)
        .navigationBarTitleDisplayMode(.inline)
        .keepScreenAwake(isPreparing)
        .task {
            gemmaManager.checkAvailability()
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

    @ViewBuilder
    private var stateContent: some View {
        switch gemmaManager.state {
        case .notDownloaded:
            notDownloadedView
        case .downloading(let progress):
            downloadingView(progress: progress)
        case .downloaded:
            compilingView
        case .compiling:
            compilingView
        case .ready:
            manageView
        case .failed(let message):
            failedView(message: message)
        }
    }

    // MARK: - Not Downloaded

    private var notDownloadedView: some View {
        VStack(spacing: Spacing.n32) {
            Spacer()

            VStack(spacing: Spacing.n32) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(colors.accent)

                Text(Localized.Onboarding.LocalModel.description)
                    .typography(Typography.body)
                    .foregroundStyle(colors.text.standard.muted)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            AppButton(Localized.Onboarding.ModelSetup.downloadAction) {
                Task { await gemmaManager.download() }
            }
        }
    }

    // MARK: - Downloading

    private func downloadingView(progress: Double) -> some View {
        VStack(spacing: Spacing.n32) {
            Spacer()

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

            Text(Localized.LocalModel.downloadBackgroundHint)
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.muted)
                .multilineTextAlignment(.center)

            Spacer()

            AppButton(Localized.Common.Actions.cancel) {
                gemmaManager.cancel()
            }
        }
    }

    // MARK: - Compiling / Preparing

    private var compilingView: some View {
        VStack(spacing: Spacing.n32) {
            Spacer()

            Image(systemName: "rectangle.3.group")
                .font(.system(size: 56))
                .foregroundStyle(colors.accent)
                .symbolEffect(.breathe, options: .repeating)

            Text(Localized.Status.preparingDevice)
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.muted)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Manage (Ready)

    private var manageView: some View {
        VStack(spacing: Spacing.n32) {
            Spacer()

            VStack(spacing: Spacing.n32) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(colors.accent)

                Text(Localized.Onboarding.ModelSetup.readyStatus)
                    .typography(Typography.titleM)
                    .foregroundStyle(colors.text.standard.base)
            }

            Spacer()

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
            }
        }
    }

    // MARK: - Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: Spacing.n32) {
            Spacer()

            VStack(spacing: Spacing.n32) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(colors.text.standard.error)

                VStack(spacing: Spacing.n8) {
                    Text(Localized.Onboarding.ModelSetup.errorTitle)
                        .typography(Typography.titleM)
                        .foregroundStyle(colors.text.standard.base)
                    Text(message)
                        .typography(Typography.note)
                        .foregroundStyle(colors.text.standard.muted)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            AppButton(Localized.Common.Actions.retry) {
                Task { await gemmaManager.download() }
            }
        }
    }

    // MARK: - Actions

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
