import Factory
import SwiftUI

/// Connects the agent to inference. Eigin Cloud is the default: choosing it
/// presents the credits sheet (the relay runs on credits). Connecting your own
/// provider is secondary. Running offline opens a sheet that kicks off the
/// background model download and returns you here to still pick a provider for
/// this conversation — the cloud always powers onboarding; the local model takes
/// over later once it's ready.
///
/// Provider construction is centralized in the coordinator; this screen reports
/// the user's choice and owns the credits and download sheets.
struct OnboardingInference: View {
    let onUseCloud: () -> Void
    let onConnectOwn: (Provider) -> Void

    @Environment(\.colors) private var colors
    @Injected(\.gemmaModelManager) private var gemmaManager: any GemmaModelManaging
    @State private var creditsModel = EiginCreditsModel()

    @State private var showCredits = false
    @State private var showDownload = false
    @State private var showProviderSelect = false
    @State private var showProviderConnect = false
    @State private var selectedMode: ProviderConnectSheetContent.Mode?

    private var offlineAvailable: Bool {
        gemmaManager.isSupported && gemmaManager.state == .notDownloaded
    }

    private var isFailed: Bool {
        if case .failed = gemmaManager.state { return true }
        return false
    }

    /// The sheet offers an action while nothing is under way: a first
    /// download, or another go after a failure.
    private var offerable: Bool {
        offlineAvailable || isFailed
    }

    private var connectSheetTitle: String {
        switch selectedMode {
        case .preset(let preset, _): preset.name
        case .custom: Localized.Provider.Picker.customProvider
        case nil: ""
        }
    }

    private var connectSheetDescription: String? {
        switch selectedMode {
        case .preset(let preset, _): preset.helpText
        case .custom: Localized.Provider.Setup.Custom.apiRequirement
        case nil: nil
        }
    }

    var body: some View {
        VStack(spacing: Spacing.n16) {
            Spacer()

            if offlineAvailable {
                Button { showDownload = true } label: {
                    Text(Localized.Onboarding.Inference.offlineLink)
                        .typography(Typography.navTab)
                        .foregroundStyle(colors.text.standard.link)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(Localized.Onboarding.Inference.useEiginButton) { useEigin() }
                AppButton(Localized.Onboarding.Inference.connectOwnButton, variant: .secondary) {
                    showProviderSelect = true
                }
            }
        }
        .task { await creditsModel.onAppear() }
        .appSheet(
            isPresented: $showCredits,
            title: Localized.Provider.Eigin.getCreditsTitle,
            description: Localized.Provider.Eigin.getCreditsDescription,
            fitsContent: true
        ) {
            // Only an actual purchase proceeds; dismissing the sheet stays put.
            GetCreditsSheetContent(model: creditsModel) {
                showCredits = false
                onUseCloud()
            }
        }
        .appSheet(
            isPresented: $showDownload,
            title: Localized.Onboarding.Inference.offlineSheetTitle,
            detents: [.medium],
            fitsContent: true
        ) {
            offlineSheet
        }
        .appSheet(
            isPresented: $showProviderSelect,
            title: Localized.Provider.typeLabel,
            description: Localized.Onboarding.Provider.cloudExplanation,
            detents: [.large]
        ) {
            ProviderSelectSheetContent { selection in
                showProviderSelect = false
                switch selection {
                case .preset(let preset, let method):
                    selectedMode = .preset(preset, method: method)
                case .custom: selectedMode = .custom
                }
                showProviderConnect = true
            }
        }
        .appSheet(
            isPresented: $showProviderConnect,
            title: connectSheetTitle,
            description: connectSheetDescription,
            detents: [.large],
            fitsContent: true
        ) {
            if let mode = selectedMode {
                ProviderConnectSheetContent(
                    mode: mode,
                    onComplete: { provider in
                        showProviderConnect = false
                        selectedMode = nil
                        onConnectOwn(provider)
                    },
                    onBack: {
                        showProviderConnect = false
                        selectedMode = nil
                        showProviderSelect = true
                    }
                )
            }
        }
    }

    /// Uses Eigin Cloud. Proceeds straight away when the user already has
    /// credits; otherwise presents the credits sheet to get some first.
    private func useEigin() {
        if creditsModel.totalCredits > 0 {
            onUseCloud()
        } else {
            showCredits = true
        }
    }

    /// The offline download sheet: the Gemma asset row, the pitch, and one
    /// button. Layout never moves — the copy and the button swap in place
    /// once the download starts.
    private var offlineSheet: some View {
        VStack(spacing: Spacing.n24) {
            AssetRow(asset: gemmaManager, showsAction: false)

            Text(
                offerable
                    ? Localized.Onboarding.Inference.offlineSheetText
                    : Localized.Onboarding.Inference.offlineDownloadingText
            )
            .typography(Typography.description)
            .foregroundStyle(colors.text.standard.muted)
            .fixedSize(horizontal: false, vertical: true)

            if offerable {
                AppButton(
                    isFailed
                        ? Localized.Common.Actions.retry
                        : Localized.Common.Actions.download
                ) {
                    Haptics.light()
                    Task { await gemmaManager.download() }
                }
            } else {
                AppButton(Localized.Onboarding.Inference.continueButton) {
                    showDownload = false
                }
            }
        }
        .padding(.horizontal, Spacing.n24)
    }
}

#Preview {
    OnboardingScaffold(
        progress: 0.28,
        title: Localized.Onboarding.Flow.Inference.title,
        text: Localized.Onboarding.Flow.Inference.text
    ) {
        OnboardingInference(onUseCloud: {}, onConnectOwn: { _ in })
    }
    .resolveTheme()
}
